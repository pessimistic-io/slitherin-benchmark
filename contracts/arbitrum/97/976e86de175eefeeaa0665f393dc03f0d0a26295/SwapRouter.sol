// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./Ownable.sol";
import "./IERC20.sol";
import "./UniversalERC20.sol";

contract SwapRouter is Ownable {
    using UniversalERC20 for IERC20;

    event TreasuryUpdated(address indexed treasury);
    event FeeRatioUpdated(uint256 feeRatio);

    uint256 constant DENOMINATOR = 10000;
    uint256 public feeRatio;

    address public treasury;

    mapping(address => bool) public isWhiteListed;

    constructor(address _treasury, uint256 _feeRatio) {
        treasury = _treasury;
        feeRatio = _feeRatio;
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;

        emit TreasuryUpdated(_treasury);
    }

    function setFeeRatio(uint256 _feeRatio) external onlyOwner {
        feeRatio = _feeRatio;

        emit FeeRatioUpdated(_feeRatio);
    }

    function addWhiteList(address contractAddr) external onlyOwner {
        isWhiteListed[contractAddr] = true;
    }

    function removeWhiteList(address contractAddr) external onlyOwner {
        isWhiteListed[contractAddr] = false;
    }

    function externalSwap(
        address fromToken,
        address toToken,
        address approveTarget,
        address swapTarget,
        uint256 amount,
        uint256 minReturnAmount,
        bytes memory callDataConcat
    ) external payable returns (uint256 returnAmount) {
        require(minReturnAmount != 0, "zero minAmount");
        require(isWhiteListed[swapTarget], "Not Whitelist Contract");

        IERC20(fromToken).universalTransferFrom(msg.sender, amount);
        IERC20(fromToken).universalApprove(approveTarget, amount);

        (bool success, ) = swapTarget.call{
            value: IERC20(fromToken).isETH() ? amount : 0
        }(callDataConcat);

        require(success, "External Swap execution Failed");

        returnAmount = IERC20(toToken).universalBalanceOf(address(this));

        uint256 fee = (returnAmount * feeRatio) / DENOMINATOR;

        if (fee != 0) {
            IERC20(toToken).universalTransfer(treasury, fee);
        }

        require(returnAmount >= minReturnAmount, "Return amount is not enough");

        IERC20(toToken).universalTransfer(msg.sender, returnAmount - fee);
    }

    receive() external payable {}
}

