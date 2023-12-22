// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./SafeMath.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./Constant.sol";
import "./IBEP20.sol";
import "./IValidator.sol";
import "./IRateModel.sol";
import "./IGToken.sol";
import "./ICore.sol";
import "./IMarketView.sol";

contract MarketView is IMarketView, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */

    mapping(address => IRateModel) public rateModel;

    /* ========== INITIALIZER ========== */

    receive() external payable {}

    function initialize() external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setRateModel(address gToken, address _rateModel) public onlyOwner {
        require(_rateModel != address(0), "MarketView: invalid rate model address");
        rateModel[gToken] = IRateModel(_rateModel);
    }

    /* ========== VIEWS ========== */

    function borrowRatePerSec(address gToken) external view override returns (uint256) {
        Constant.AccrueSnapshot memory snapshot = pendingAccrueSnapshot(IGToken(gToken));
        return rateModel[gToken].getBorrowRate(IGToken(gToken).getCash(), snapshot.totalBorrow, snapshot.totalReserve);
    }

    function supplyRatePerSec(address gToken) external view override returns (uint256) {
        Constant.AccrueSnapshot memory snapshot = pendingAccrueSnapshot(IGToken(gToken));
        return
            rateModel[gToken].getSupplyRate(
                IGToken(gToken).getCash(),
                snapshot.totalBorrow,
                snapshot.totalReserve,
                IGToken(gToken).reserveFactor()
            );
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function pendingAccrueSnapshot(IGToken gToken) internal view returns (Constant.AccrueSnapshot memory) {
        Constant.AccrueSnapshot memory snapshot;
        snapshot.totalBorrow = gToken._totalBorrow();
        snapshot.totalReserve = gToken.totalReserve();
        snapshot.accInterestIndex = gToken.accInterestIndex();

        uint256 reserveFactor = gToken.reserveFactor();
        uint256 lastAccruedTime = gToken.lastAccruedTime();

        if (block.timestamp > lastAccruedTime && snapshot.totalBorrow > 0) {
            uint256 borrowRate = rateModel[address(gToken)].getBorrowRate(
                gToken.getCash(),
                snapshot.totalBorrow,
                snapshot.totalReserve
            );
            uint256 interestFactor = borrowRate.mul(block.timestamp.sub(lastAccruedTime));
            uint256 pendingInterest = snapshot.totalBorrow.mul(interestFactor).div(1e18);

            snapshot.totalBorrow = snapshot.totalBorrow.add(pendingInterest);
            snapshot.totalReserve = snapshot.totalReserve.add(pendingInterest.mul(reserveFactor).div(1e18));
            snapshot.accInterestIndex = snapshot.accInterestIndex.add(
                interestFactor.mul(snapshot.accInterestIndex).div(1e18)
            );
        }
        return snapshot;
    }
}

