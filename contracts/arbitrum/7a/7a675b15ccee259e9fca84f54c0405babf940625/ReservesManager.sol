// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./IMount.sol";
import "./SafeMath.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";

contract ReservesManager is Initializable, OwnableUpgradeable {
    using SafeMath for uint256;

    uint256 public sellBurnFee;
    uint256 public sellReservesFee;
    uint256 public sellTotalFees;

    uint256 public buyBurnFee;
    uint256 public buyReservesFee;
    uint256 public buyTotalFees;

    uint256 public reservesFees;

    IMount public mountContract;
    address public mountAddress;

    function initialize() external initializer {
        __Ownable_init();

        reservesFees = 3;
        sellBurnFee = 2;
        sellTotalFees = sellBurnFee + reservesFees;

        buyBurnFee = 2;
        buyTotalFees = buyBurnFee + reservesFees;
    }

    // Main burn and fees algorithm, might change for optimisation
    function estimateFees(
        bool _isSelling,
        bool _isBuying,
        uint256 _amount
    ) external view returns (uint256, uint256) {
        require(_msgSender() == mountAddress, "Not Mount contract");

        uint256 fees = 0;
        uint256 tokensForBurn = 0;

        // On sell
        if (_isSelling && sellTotalFees > 0) {
            fees = _amount.mul(sellTotalFees).div(100);
            tokensForBurn += (fees * sellBurnFee) / sellTotalFees;
        }
        // On buy
        else if (_isBuying && buyTotalFees > 0) {
            fees = _amount.mul(buyTotalFees).div(100);
            tokensForBurn += (fees * buyBurnFee) / buyTotalFees;
        }

        return (fees, tokensForBurn);
    }

    function updateReservesFees(uint256 _reservesFees) external onlyOwner {
        require(
            _reservesFees > 0 && _reservesFees <= 5,
            "Must keep fees between 0 and 5"
        );
        reservesFees = _reservesFees;
    }

    function updateSellFees(uint256 _burnFee) external onlyOwner {
        sellBurnFee = _burnFee;
        sellTotalFees = sellBurnFee + reservesFees;
        require(sellTotalFees <= 5, "Must keep fees at 5% or less");
    }

    function updateBuyFees(uint256 _burnFee) external onlyOwner {
        buyBurnFee = _burnFee;
        buyTotalFees = buyBurnFee + reservesFees;
        require(buyTotalFees <= 8, "Must keep fees at 8% or less");
    }

    function updateMountAddress(address _newAddr) external onlyOwner {
        require(_newAddr != address(0xdead), "Can't be dead address");
        mountContract = IMount(_newAddr);
        mountAddress = _newAddr;
    }
}
