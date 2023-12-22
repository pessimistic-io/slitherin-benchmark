// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface IPSM {
    function setSmartVault(address _newVault) external;

    function setFeeRecipient(address _feeRecipient) external;

    function setDebtLimit(uint256 _newDebtLimit) external;

    function toggleRedeemPaused(bool _paused) external;

    function setFee(uint256 _newSwapFee) external;

    function redeemSTAR(
        uint256 _starAmount,
        address _recipient
    ) external returns (uint256 usdcAmount);

    function mintSTAR(
        uint256 _usdcAmount,
        address _recipient
    ) external returns (uint256 starAmount);
}

interface IERC20Override {
    function decimals() external returns (uint8);
}

