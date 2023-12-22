// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./IERC20.sol";
import "./SafeERC20.sol";

import "./IAavePoolV3.sol";

library AaveLogic {
    using SafeERC20 for IERC20;

    event SupplyAave(address supplyToken, uint256 supplyAmount);
    event BorrowAave(address borrowToken, uint256 borrowAmount);
    event RepayAave(address repayToken, uint256 repayAmount);
    event WithdrawAave(address withdrawToken, uint256 withdrawAmount);

    function supply(
        address aaveV3,
        address _supplyToken,
        uint256 _supplyAmount,
        uint16 _referralCode
    ) internal {
        IERC20(_supplyToken).safeApprove(aaveV3, 0);
        IERC20(_supplyToken).safeApprove(aaveV3, _supplyAmount);
        IAavePoolV3(aaveV3).supply(
            _supplyToken,
            _supplyAmount,
            address(this),
            _referralCode
        );
        emit SupplyAave(_supplyToken, _supplyAmount);
    }

    function borrow(
        address aaveV3,
        uint256 minHealthFactor,
        address _borrowToken,
        uint256 _borrowAmount,
        uint16 _referralCode
    ) internal {
        IAavePoolV3(aaveV3).borrow(
            _borrowToken,
            _borrowAmount,
            2,
            _referralCode,
            address(this)
        );
        (, , , , , uint256 healthFactor) = IAavePoolV3(aaveV3)
            .getUserAccountData(address(this));
        require(healthFactor >= minHealthFactor, "health factor too low");
        emit BorrowAave(_borrowToken, _borrowAmount);
    }

    function repayArgs(uint16 assetId, uint256 _repayAmount)internal pure returns (bytes32){
        uint8 interestRateMode = 2;
        bytes memory _args = abi.encodePacked(
            bytes14(uint112(interestRateMode)),
            bytes16(uint128(_repayAmount)),
            bytes2(assetId)
        );
        bytes32 args;
        assembly {
            args := mload(add(_args, 32))
        }
        return args;
    }

    function repay(address aaveV3, address _repayToken, uint256 _repayAmount) internal {
        IERC20(_repayToken).safeApprove(aaveV3, 0);
        IERC20(_repayToken).safeApprove(aaveV3, _repayAmount);
        uint16 assetId = getAssetId(aaveV3, _repayToken);
        IAavePoolV3(aaveV3).repay(repayArgs(assetId, _repayAmount));
        emit RepayAave(_repayToken, _repayAmount);
    }

    function getAssetId(address aaveV3, address _token) internal view returns (uint16) {
        address[] memory reserves = IAavePoolV3(aaveV3).getReservesList();
        for (uint i = 0; i < reserves.length; i++) {
            if (reserves[i] == _token) {
                return uint16(i);
            }
        }
        revert("token not found");
    }

    function withdrawArgs(uint16 assetId, uint256 _withdrawAmount) internal pure returns (bytes32){
        bytes memory _args = abi.encodePacked(
            bytes30(uint240(_withdrawAmount)),
            bytes2(assetId)
        );
        bytes32 args;
        assembly {
            args := mload(add(_args, 32))
        }
        return args;
    }

    function withdraw(
        address aaveV3,
        uint256 minHealthFactor,
        address _withdrawToken,
        uint256 _withdrawAmount
    ) internal {
        uint16 assetId = getAssetId(aaveV3, _withdrawToken);
        IAavePoolV3(aaveV3).withdraw(withdrawArgs(assetId, _withdrawAmount));
        (, , , , , uint256 healthFactor) = IAavePoolV3(aaveV3)
            .getUserAccountData(address(this));
        require(healthFactor >= minHealthFactor, "health factor too low");
        emit WithdrawAave(_withdrawToken, _withdrawAmount);
    }

    // 0: Disable E-Mode, 1: stable coin, 2: eth correlated
    function setUserEMode(address aaveV3,uint256 minHealthFactor,uint8 categoryId) internal {
        IAavePoolV3(aaveV3).setUserEMode(categoryId);
        (, , , , , uint256 healthFactor) = IAavePoolV3(aaveV3)
            .getUserAccountData(address(this));
        require(healthFactor >= minHealthFactor, "health factor too low");
    }
}
