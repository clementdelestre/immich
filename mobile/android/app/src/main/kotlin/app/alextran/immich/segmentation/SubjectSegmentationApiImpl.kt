package app.alextran.immich.segmentation

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Rect
import androidx.core.content.FileProvider
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.ByteBufferExtractor
import com.google.mediapipe.tasks.components.containers.NormalizedKeypoint
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.interactivesegmenter.InteractiveSegmenter
import com.google.mediapipe.tasks.vision.interactivesegmenter.InteractiveSegmenterOptions
import com.google.mediapipe.tasks.vision.interactivesegmenter.Stroke
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors

private const val MAX_SIDE = 3072

class SubjectSegmentationApiImpl(private val ctx: Context) : SubjectSegmentationApi {
  private val executor = Executors.newSingleThreadExecutor()

  private val segmenter by lazy {
    val options = InteractiveSegmenterOptions.builder()
      .setBaseOptions(BaseOptions.builder().setModelAssetPath("interactive_segmentation.task").build())
      .build()
    InteractiveSegmenter.createFromOptions(ctx, options)
  }

  override fun extractSubject(
    rgba: ByteArray,
    width: Long,
    height: Long,
    x: Double,
    y: Double,
    callback: (Result<SubjectCutout?>) -> Unit
  ) {
    executor.execute {
      callback(runCatching { extract(rgba, width.toInt(), height.toInt(), x.toFloat(), y.toFloat()) })
    }
  }

  override fun copyImageToClipboard(path: String) {
    val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.stickers", File(path))
    val clipboard = ctx.getSystemService(ClipboardManager::class.java)
    clipboard.setPrimaryClip(ClipData.newUri(ctx.contentResolver, "sticker", uri))
  }

  private inline fun segment(bitmap: Bitmap, x: Float, y: Float, onPixel: (Int, Int, Boolean) -> Unit) {
    segmenter.setImage(BitmapImageBuilder(bitmap).build())
    val stroke = Stroke.builder()
      .setBrushMode(Stroke.BrushMode.POSITIVE)
      .setPoints(listOf(NormalizedKeypoint.create(x, y)))
      .setCompleted(true)
      .build()
    val maskImage = segmenter.segment(listOf(stroke))
    val maskWidth = maskImage.width
    val maskHeight = maskImage.height
    val mask = ByteBufferExtractor.extract(maskImage).order(ByteOrder.nativeOrder()).asFloatBuffer()
    val width = bitmap.width
    val height = bitmap.height
    for (py in 0 until height) {
      val row = (py * maskHeight / height) * maskWidth
      for (px in 0 until width) {
        onPixel(px, py, mask.get(row + px * maskWidth / width) > 0.5f)
      }
    }
  }

  private fun extract(rgba: ByteArray, sourceWidth: Int, sourceHeight: Int, x: Float, y: Float): SubjectCutout? {
    val full = Bitmap.createBitmap(sourceWidth, sourceHeight, Bitmap.Config.ARGB_8888)
    full.copyPixelsFromBuffer(ByteBuffer.wrap(rgba))
    val scale = minOf(1f, MAX_SIDE.toFloat() / maxOf(sourceWidth, sourceHeight))
    val source = if (scale < 1f) {
      Bitmap.createScaledBitmap(full, (sourceWidth * scale).toInt(), (sourceHeight * scale).toInt(), true)
    } else {
      full
    }
    val width = source.width
    val height = source.height

    val n = width * height
    val seed = (y * (height - 1)).toInt() * width + (x * (width - 1)).toInt()
    val subject = BooleanArray(n)
    segment(source, x, y) { px, py, inside -> subject[py * width + px] = inside }
    cleanUpMask(subject, width, height, seed)

    // The model works on a 768px input, a second pass cropped to the subject gives sharper edges.
    val bounds = maskBounds(subject, width, height) ?: return null
    val marginX = bounds.width() * 3 / 20 + 8
    val marginY = bounds.height() * 3 / 20 + 8
    val crop = Rect(
      maxOf(0, bounds.left - marginX),
      maxOf(0, bounds.top - marginY),
      minOf(width, bounds.right + marginX),
      minOf(height, bounds.bottom + marginY)
    )
    if (crop.width() * crop.height() < n * 3 / 5) {
      val zoomed = Bitmap.createBitmap(source, crop.left, crop.top, crop.width(), crop.height())
      val zx = (x * (width - 1) - crop.left) / crop.width()
      val zy = (y * (height - 1) - crop.top) / crop.height()
      subject.fill(false)
      segment(zoomed, zx, zy) { px, py, inside -> subject[(crop.top + py) * width + crop.left + px] = inside }
      cleanUpMask(subject, width, height, seed)
    }

    val subjectBounds = maskBounds(subject, width, height) ?: return null
    // The anti-aliased edge spills one pixel outside the mask.
    val box = Rect(
      maxOf(0, subjectBounds.left - 1),
      maxOf(0, subjectBounds.top - 1),
      minOf(width, subjectBounds.right + 1),
      minOf(height, subjectBounds.bottom + 1)
    )
    val pixels = IntArray(box.width() * box.height())
    source.getPixels(pixels, 0, box.width(), box.left, box.top, box.width(), box.height())
    for (py in 0 until box.height()) {
      for (px in 0 until box.width()) {
        val i = py * box.width() + px
        val alpha = edgeAlpha(subject, width, height, box.left + px, box.top + py)
        pixels[i] = (pixels[i] and 0xFFFFFF) or (alpha shl 24)
      }
    }

    val sticker = Bitmap.createBitmap(pixels, box.width(), box.height(), Bitmap.Config.ARGB_8888)
    val png = ByteArrayOutputStream().use {
      sticker.compress(Bitmap.CompressFormat.PNG, 100, it)
      it.toByteArray()
    }
    return SubjectCutout(
      png,
      box.left.toDouble() / width,
      box.top.toDouble() / height,
      box.width().toDouble() / width,
      box.height().toDouble() / height
    )
  }
}

// Keeps the region under the touch point and fills small holes left by low confidence patches.
private fun cleanUpMask(subject: BooleanArray, width: Int, height: Int, seed: Int) {
  val n = width * height
  val queue = IntArray(n)
  if (subject[seed]) {
    val region = BooleanArray(n)
    floodFill(width, height, intArrayOf(seed), region, queue) { subject[it] }
    region.copyInto(subject)
  }

  val outside = BooleanArray(n)
  val border = IntArray(2 * width + 2 * height) {
    when {
      it < width -> it
      it < 2 * width -> n - 1 - (it - width)
      it < 2 * width + height -> (it - 2 * width) * width
      else -> (it - 2 * width - height) * width + width - 1
    }
  }
  floodFill(width, height, border, outside, queue) { !subject[it] }

  // Bigger holes are real gaps, e.g. between an arm and the body.
  val maxHole = subject.count { it } / 50
  val hole = BooleanArray(n)
  for (i in 0 until n) {
    if (subject[i] || outside[i] || hole[i]) continue
    val size = floodFill(width, height, intArrayOf(i), hole, queue) { !subject[it] }
    if (size <= maxHole) {
      for (k in 0 until size) subject[queue[k]] = true
    }
  }
}

// Filled pixels are left in queue[0 until result].
private inline fun floodFill(
  width: Int,
  height: Int,
  seeds: IntArray,
  visited: BooleanArray,
  queue: IntArray,
  include: (Int) -> Boolean
): Int {
  val n = width * height
  var head = 0
  var tail = 0
  for (s in seeds) {
    if (!visited[s] && include(s)) {
      visited[s] = true
      queue[tail++] = s
    }
  }
  while (head < tail) {
    val i = queue[head++]
    val x = i % width
    for (d in 0 until 4) {
      val j = when (d) {
        0 -> if (x > 0) i - 1 else -1
        1 -> if (x < width - 1) i + 1 else -1
        2 -> i - width
        else -> i + width
      }
      if (j < 0 || j >= n || visited[j] || !include(j)) continue
      visited[j] = true
      queue[tail++] = j
    }
  }
  return tail
}

private fun edgeAlpha(subject: BooleanArray, width: Int, height: Int, x: Int, y: Int): Int {
  var count = 0
  for (dy in -1..1) {
    val yy = (y + dy).coerceIn(0, height - 1)
    for (dx in -1..1) {
      if (subject[yy * width + (x + dx).coerceIn(0, width - 1)]) count++
    }
  }
  return count * 255 / 9
}

private fun maskBounds(subject: BooleanArray, width: Int, height: Int): Rect? {
  var minX = width; var minY = height; var maxX = -1; var maxY = -1
  for (py in 0 until height) {
    for (px in 0 until width) {
      if (!subject[py * width + px]) continue
      if (px < minX) minX = px
      if (px > maxX) maxX = px
      if (py < minY) minY = py
      if (py > maxY) maxY = py
    }
  }
  return if (maxX < 0) null else Rect(minX, minY, maxX + 1, maxY + 1)
}
