-- NOTE: This file is auto generated by ./sql-generator

-- SessionRepository.getByToken
SELECT DISTINCT
  "distinctAlias"."SessionEntity_id" AS "ids_SessionEntity_id"
FROM
  (
    SELECT
      "SessionEntity"."id" AS "SessionEntity_id",
      "SessionEntity"."userId" AS "SessionEntity_userId",
      "SessionEntity"."createdAt" AS "SessionEntity_createdAt",
      "SessionEntity"."updatedAt" AS "SessionEntity_updatedAt",
      "SessionEntity"."deviceType" AS "SessionEntity_deviceType",
      "SessionEntity"."deviceOS" AS "SessionEntity_deviceOS",
      "SessionEntity__SessionEntity_user"."id" AS "SessionEntity__SessionEntity_user_id",
      "SessionEntity__SessionEntity_user"."name" AS "SessionEntity__SessionEntity_user_name",
      "SessionEntity__SessionEntity_user"."avatarColor" AS "SessionEntity__SessionEntity_user_avatarColor",
      "SessionEntity__SessionEntity_user"."isAdmin" AS "SessionEntity__SessionEntity_user_isAdmin",
      "SessionEntity__SessionEntity_user"."email" AS "SessionEntity__SessionEntity_user_email",
      "SessionEntity__SessionEntity_user"."storageLabel" AS "SessionEntity__SessionEntity_user_storageLabel",
      "SessionEntity__SessionEntity_user"."oauthId" AS "SessionEntity__SessionEntity_user_oauthId",
      "SessionEntity__SessionEntity_user"."profileImagePath" AS "SessionEntity__SessionEntity_user_profileImagePath",
      "SessionEntity__SessionEntity_user"."shouldChangePassword" AS "SessionEntity__SessionEntity_user_shouldChangePassword",
      "SessionEntity__SessionEntity_user"."createdAt" AS "SessionEntity__SessionEntity_user_createdAt",
      "SessionEntity__SessionEntity_user"."deletedAt" AS "SessionEntity__SessionEntity_user_deletedAt",
      "SessionEntity__SessionEntity_user"."status" AS "SessionEntity__SessionEntity_user_status",
      "SessionEntity__SessionEntity_user"."updatedAt" AS "SessionEntity__SessionEntity_user_updatedAt",
      "SessionEntity__SessionEntity_user"."memoriesEnabled" AS "SessionEntity__SessionEntity_user_memoriesEnabled",
      "SessionEntity__SessionEntity_user"."quotaSizeInBytes" AS "SessionEntity__SessionEntity_user_quotaSizeInBytes",
      "SessionEntity__SessionEntity_user"."quotaUsageInBytes" AS "SessionEntity__SessionEntity_user_quotaUsageInBytes"
    FROM
      "sessions" "SessionEntity"
      LEFT JOIN "users" "SessionEntity__SessionEntity_user" ON "SessionEntity__SessionEntity_user"."id" = "SessionEntity"."userId"
      AND (
        "SessionEntity__SessionEntity_user"."deletedAt" IS NULL
      )
    WHERE
      (("SessionEntity"."token" = $1))
  ) "distinctAlias"
ORDER BY
  "SessionEntity_id" ASC
LIMIT
  1

-- SessionRepository.delete
DELETE FROM "sessions"
WHERE
  "id" = $1
