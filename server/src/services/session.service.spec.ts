import { ILoggerRepository } from 'src/interfaces/logger.interface';
import { ISessionRepository } from 'src/interfaces/session.interface';
import { SessionService } from 'src/services/session.service';
import { authStub } from 'test/fixtures/auth.stub';
import { sessionStub } from 'test/fixtures/session.stub';
import { IAccessRepositoryMock, newAccessRepositoryMock } from 'test/repositories/access.repository.mock';
import { newLoggerRepositoryMock } from 'test/repositories/logger.repository.mock';
import { newSessionRepositoryMock } from 'test/repositories/session.repository.mock';
import { Mocked } from 'vitest';

describe('SessionService', () => {
  let sut: SessionService;
  let accessMock: Mocked<IAccessRepositoryMock>;
  let loggerMock: Mocked<ILoggerRepository>;
  let sessionMock: Mocked<ISessionRepository>;

  beforeEach(() => {
    accessMock = newAccessRepositoryMock();
    loggerMock = newLoggerRepositoryMock();
    sessionMock = newSessionRepositoryMock();

    sut = new SessionService(accessMock, loggerMock, sessionMock);
  });

  it('should be defined', () => {
    expect(sut).toBeDefined();
  });

  describe('getAll', () => {
    it('should get the devices', async () => {
      sessionMock.getByUserId.mockResolvedValue([sessionStub.valid, sessionStub.inactive]);
      await expect(sut.getAll(authStub.user1)).resolves.toEqual([
        {
          createdAt: '2021-01-01T00:00:00.000Z',
          current: true,
          deviceOS: '',
          deviceType: '',
          id: 'token-id',
          updatedAt: expect.any(String),
        },
        {
          createdAt: '2021-01-01T00:00:00.000Z',
          current: false,
          deviceOS: 'Android',
          deviceType: 'Mobile',
          id: 'not_active',
          updatedAt: expect.any(String),
        },
      ]);

      expect(sessionMock.getByUserId).toHaveBeenCalledWith(authStub.user1.user.id);
    });
  });

  describe('logoutDevices', () => {
    it('should logout all devices', async () => {
      sessionMock.getByUserId.mockResolvedValue([sessionStub.inactive, sessionStub.valid]);

      await sut.deleteAll(authStub.user1);

      expect(sessionMock.getByUserId).toHaveBeenCalledWith(authStub.user1.user.id);
      expect(sessionMock.delete).toHaveBeenCalledWith('not_active');
      expect(sessionMock.delete).not.toHaveBeenCalledWith('token-id');
    });
  });

  describe('logoutDevice', () => {
    it('should logout the device', async () => {
      accessMock.authDevice.checkOwnerAccess.mockResolvedValue(new Set(['token-1']));

      await sut.delete(authStub.user1, 'token-1');

      expect(accessMock.authDevice.checkOwnerAccess).toHaveBeenCalledWith(authStub.user1.user.id, new Set(['token-1']));
      expect(sessionMock.delete).toHaveBeenCalledWith('token-1');
    });
  });
});
