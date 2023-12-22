// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IMaotai } from "./IMaotai.sol";
import { IRum } from "./IRum.sol";
import { ISake } from "./ISake.sol";
import { ISakeV1 } from "./ISakeV1.sol";
import { IVodka } from "./IVodka.sol";
import { IVodkaV2 } from "./IVodkaV2.sol";
import { IWhiskey } from "./IWhiskey.sol";
import { IVault } from "./IVault.sol";

import "./console.sol";

contract VaultkaMulticall {
  mapping(string => address) public vaultAddresses;

  /* ##################################################################
                            HELPERS
  ################################################################## */
  function setVaultAddress(string memory vault, address vaultAddress) external {
    vaultAddresses[vault] = vaultAddress;
  }

  function setVaultAddresses(string[] memory vaults, address[] memory addresses) external {
    require(vaults.length == addresses.length, "length not match");

    for (uint256 i = 0; i < vaults.length; i++) {
      vaultAddresses[vaults[i]] = addresses[i];
    }
  }

  function getVaultAddress(string memory vault) external view returns (address) {
    return vaultAddresses[vault];
  }

  function areStringsEqual(string memory str1, string memory str2) internal pure returns (bool) {
    return keccak256(bytes(str1)) == keccak256(bytes(str2));
  }

  /* ##################################################################
                            INTERNAL
  ################################################################## */
  function _getNumberOfPositions(string memory _vault, address _user) internal view returns (uint256) {
    address vaultAddress = vaultAddresses[_vault];

    if (areStringsEqual(_vault, "maotai")) return IMaotai(vaultAddress).getTotalNumbersOfOpenPosition(_user);
    if (areStringsEqual(_vault, "rum")) return IRum(vaultAddress).getNumbersOfPosition(_user);
    if (areStringsEqual(_vault, "sake")) return ISake(vaultAddress).getTotalNumbersOfOpenPositionBy(_user);
    if (areStringsEqual(_vault, "sakeV1")) return ISakeV1(vaultAddress).getTotalNumbersOfOpenPositionBy(_user);
    if (areStringsEqual(_vault, "vodka")) return IVodka(vaultAddress).getTotalNumbersOfOpenPositionBy(_user);
    if (areStringsEqual(_vault, "vodkaV2")) return IVodkaV2(vaultAddress).getTotalOpenPosition(_user);
    if (areStringsEqual(_vault, "whiskey")) return IWhiskey(vaultAddress).getTotalNumbersOfOpenPositionBy(_user);

    return 0;
  }

  function _getDtv(
    string memory _vault,
    uint256 _positionId,
    address _user,
    uint256 _hlpPrice
  )
    internal
    view
    returns (uint256 currentDTV, uint256 currentPosition, uint256 currentDebt, uint256 leverageAmountWithDA)
  {
    address vaultAddress = vaultAddresses[_vault];

    if (areStringsEqual(_vault, "maotai")) {
      (currentDTV, currentPosition, currentDebt) = IMaotai(vaultAddress).getUpdatedDebt(_positionId, _user);
    } else if (areStringsEqual(_vault, "rum")) {
      (currentDTV, currentDebt, currentPosition, , leverageAmountWithDA) = IRum(vaultAddress).getPosition(
        _positionId,
        _user,
        _hlpPrice
      );
    } else if (areStringsEqual(_vault, "sake")) {
      (currentDTV, currentPosition, currentDebt) = ISake(vaultAddress).getUpdatedDebt(_positionId, _user);
    } else if (areStringsEqual(_vault, "sakeV1")) {
      (currentDTV, currentPosition, currentDebt) = ISakeV1(vaultAddress).getUpdatedDebtAndValue(_positionId, _user);
    } else if (areStringsEqual(_vault, "vodka")) {
      (currentDTV, currentPosition, currentDebt) = IVodka(vaultAddress).getUpdatedDebt(_positionId, _user);
    } else if (areStringsEqual(_vault, "vodkaV2")) {
      (currentDTV, currentPosition, currentDebt) = IVodkaV2(vaultAddress).getUpdatedDebt(_positionId, _user);
      (leverageAmountWithDA, ) = IVodkaV2(vaultAddress).getCurrentLeverageAmount(_positionId, _user);
    } else if (areStringsEqual(_vault, "whiskey")) {
      (currentDTV, currentPosition, currentDebt) = IWhiskey(vaultAddress).getUpdatedDebtAndValue(_positionId, _user);
    }
  }

  // function _getUserInfo(
  //   string memory _vault,
  //   uint256 _positionId,
  //   address _user
  // )
  //   public
  //   view
  //   returns (
  //     IMaotai.UserInfo memory maotaiInfo,
  //     IRum.PositionInfo memory rumInfo,
  //     ISake.UserInfo memory sakeInfo,
  //     ISakeV1.UserInfo memory sakeV1Info,
  //     IVodka.UserInfo memory vodkaInfo,
  //     IVodkaV2.PositionInfo memory vodkaV2Info,
  //     IWhiskey.UserInfo memory whiskeyInfo
  //   )
  // {
  //   address vaultAddress = vaultAddresses[_vault];

  //   if (areStringsEqual(_vault, "maotai")) {
  //     maotaiInfo = IMaotai(vaultAddress).userInfo(_user, _positionId);
  //   } else if (areStringsEqual(_vault, "rum")) {
  //     rumInfo = IRum(vaultAddress).positionInfo(_user, _positionId);
  //   } else if (areStringsEqual(_vault, "sake")) {
  //     sakeInfo = ISake(vaultAddress).userInfo(_user, _positionId);
  //   } else if (areStringsEqual(_vault, "sakeV1")) {
  //     sakeV1Info = ISakeV1(vaultAddress).userInfo(_user, _positionId);
  //   } else if (areStringsEqual(_vault, "vodka")) {
  //     vodkaInfo = IVodka(vaultAddress).userInfo(_user, _positionId);
  //   } else if (areStringsEqual(_vault, "vodkaV2")) {
  //     vodkaV2Info = IVodkaV2(vaultAddress).positionInfo(_user, _positionId);
  //   } else if (areStringsEqual(_vault, "whiskey")) {
  //     whiskeyInfo = IWhiskey(vaultAddress).userInfo(_user, _positionId);
  //   }
  // }

  /* ##################################################################
                            MAIN
  ################################################################## */
  function fetchAllUsersDtv(
    string memory _vault,
    address[] memory _users
  ) external view returns (IVault.Dtv[][] memory) {
    address vaultAddress = vaultAddresses[_vault];
    require(vaultAddress != address(0), "dont have this vault");

    IVault.Dtv[][] memory dtv = new IVault.Dtv[][](_users.length);

    // special case for rum's getPosition
    uint256 hlpPrice = IRum(vaultAddresses["rum"]).getHLPPrice(true);

    for (uint256 i = 0; i < _users.length; i++) {
      uint256 numberOfPositions = _getNumberOfPositions(_vault, _users[i]);
      dtv[i] = new IVault.Dtv[](numberOfPositions);

      for (uint256 j = 0; j < numberOfPositions; j++) {
        (uint256 currentDTV, uint256 currentPosition, uint256 currentDebt, uint256 leverageAmountWithDA) = _getDtv(
          _vault,
          j,
          _users[i],
          hlpPrice
        );

        dtv[i][j] = IVault.Dtv({
          currentDTV: currentDTV,
          currentPosition: currentPosition,
          currentDebt: currentDebt,
          leverageAmountWithDA: leverageAmountWithDA
        });
      }
    }

    return dtv;
  }

  function fetchMaotaiAllUsersPosition(address[] memory _users) external view returns (IMaotai.UserInfo[][] memory) {
    string memory vault = "maotai";
    address vaultAddress = vaultAddresses[vault];
    require(vaultAddress != address(0), "dont have this vault");

    IMaotai.UserInfo[][] memory positions = new IMaotai.UserInfo[][](_users.length);

    for (uint256 i = 0; i < _users.length; i++) {
      uint256 numberOfPositions = _getNumberOfPositions(vault, _users[i]);
      positions[i] = new IMaotai.UserInfo[](numberOfPositions);

      for (uint256 j = 0; j < numberOfPositions; j++) {
        IMaotai.UserInfo memory positionInfo = IMaotai(vaultAddress).userInfo(_users[i], j);

        positions[i][j] = positionInfo;
      }
    }

    return positions;
  }

  function fetchRumAllUsersPosition(address[] memory _users) external view returns (IRum.PositionInfo[][] memory) {
    string memory vault = "rum";
    address vaultAddress = vaultAddresses[vault];
    require(vaultAddress != address(0), "dont have this vault");

    IRum.PositionInfo[][] memory positions = new IRum.PositionInfo[][](_users.length);

    for (uint256 i = 0; i < _users.length; i++) {
      uint256 numberOfPositions = _getNumberOfPositions(vault, _users[i]);
      positions[i] = new IRum.PositionInfo[](numberOfPositions);

      for (uint256 j = 0; j < numberOfPositions; j++) {
        IRum.PositionInfo memory positionInfo = IRum(vaultAddress).positionInfo(_users[i], j);

        positions[i][j] = positionInfo;
      }
    }

    return positions;
  }

  function fetchSakeAllUsersPosition(address[] memory _users) external view returns (ISake.UserInfo[][] memory) {
    string memory vault = "sake";
    address vaultAddress = vaultAddresses[vault];
    require(vaultAddress != address(0), "dont have this vault");

    ISake.UserInfo[][] memory positions = new ISake.UserInfo[][](_users.length);

    for (uint256 i = 0; i < _users.length; i++) {
      uint256 numberOfPositions = _getNumberOfPositions(vault, _users[i]);
      positions[i] = new ISake.UserInfo[](numberOfPositions);

      for (uint256 j = 0; j < numberOfPositions; j++) {
        ISake.UserInfo memory positionInfo = ISake(vaultAddress).userInfo(_users[i], j);

        positions[i][j] = positionInfo;
      }
    }

    return positions;
  }

  function fetchSakeV1AllUsersPosition(address[] memory _users) external view returns (ISakeV1.UserInfo[][] memory) {
    string memory vault = "sakeV1";
    address vaultAddress = vaultAddresses[vault];
    require(vaultAddress != address(0), "dont have this vault");

    ISakeV1.UserInfo[][] memory positions = new ISakeV1.UserInfo[][](_users.length);

    for (uint256 i = 0; i < _users.length; i++) {
      uint256 numberOfPositions = _getNumberOfPositions(vault, _users[i]);
      positions[i] = new ISakeV1.UserInfo[](numberOfPositions);

      for (uint256 j = 0; j < numberOfPositions; j++) {
        ISakeV1.UserInfo memory positionInfo = ISakeV1(vaultAddress).userInfo(_users[i], j);

        positions[i][j] = positionInfo;
      }
    }

    return positions;
  }

  function fetchVodkaAllUsersPosition(address[] memory _users) external view returns (IVodka.UserInfo[][] memory) {
    string memory vault = "vodka";
    address vaultAddress = vaultAddresses[vault];
    require(vaultAddress != address(0), "dont have this vault");

    IVodka.UserInfo[][] memory positions = new IVodka.UserInfo[][](_users.length);

    for (uint256 i = 0; i < _users.length; i++) {
      uint256 numberOfPositions = _getNumberOfPositions(vault, _users[i]);
      positions[i] = new IVodka.UserInfo[](numberOfPositions);

      for (uint256 j = 0; j < numberOfPositions; j++) {
        IVodka.UserInfo memory positionInfo = IVodka(vaultAddress).userInfo(_users[i], j);

        positions[i][j] = positionInfo;
      }
    }

    return positions;
  }

  function fetchVodkaV2AllUsersPosition(
    address[] memory _users
  ) external view returns (IVodkaV2.PositionInfo[][] memory) {
    string memory vault = "vodkaV2";
    address vaultAddress = vaultAddresses[vault];
    require(vaultAddress != address(0), "dont have this vault");

    IVodkaV2.PositionInfo[][] memory positions = new IVodkaV2.PositionInfo[][](_users.length);

    for (uint256 i = 0; i < _users.length; i++) {
      uint256 numberOfPositions = _getNumberOfPositions(vault, _users[i]);
      positions[i] = new IVodkaV2.PositionInfo[](numberOfPositions);

      for (uint256 j = 0; j < numberOfPositions; j++) {
        IVodkaV2.PositionInfo memory positionInfo = IVodkaV2(vaultAddress).positionInfo(_users[i], j);

        positions[i][j] = positionInfo;
      }
    }

    return positions;
  }

  function fetchWhiskeyAllUsersPosition(address[] memory _users) external view returns (IWhiskey.UserInfo[][] memory) {
    string memory vault = "whiskey";
    address vaultAddress = vaultAddresses[vault];
    require(vaultAddress != address(0), "dont have this vault");

    IWhiskey.UserInfo[][] memory positions = new IWhiskey.UserInfo[][](_users.length);

    for (uint256 i = 0; i < _users.length; i++) {
      uint256 numberOfPositions = _getNumberOfPositions(vault, _users[i]);
      positions[i] = new IWhiskey.UserInfo[](numberOfPositions);

      for (uint256 j = 0; j < numberOfPositions; j++) {
        IWhiskey.UserInfo memory positionInfo = IWhiskey(vaultAddress).userInfo(_users[i], j);

        positions[i][j] = positionInfo;
      }
    }

    return positions;
  }
}

