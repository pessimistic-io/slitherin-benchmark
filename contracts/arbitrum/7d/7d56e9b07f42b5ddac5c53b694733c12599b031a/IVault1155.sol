// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import { VaultDataTypes } from "./VaultDataTypes.sol";

interface IVault1155 {
    function initialize(address _factory, address _feeReceiver, address _addressesRegistry) external;
    function getCurrentTranche() external view returns (uint256);
    function getTotalQuote(uint256 _numShares, uint256 fee) external returns (uint256[] memory);
    function getTotalQuoteWithVIT(address _VITAddress, uint256 _numShares) external returns (uint256[] memory);
    function mintVaultToken(uint256 _numShares, uint256 _stableAmount, uint256[] calldata _amountPerSwap, VaultDataTypes.LockupPeriod _lockup) external;
    function mintVaultTokenWithVIT(uint256 _numShares, uint256 _stableAmount, uint256[] calldata _amountPerSwap, VaultDataTypes.LockupPeriod _lockup, address _mintVITAddress, uint256 _mintVITAmount) external;
    function setExchangeSwapContract(address _tokenIn, address _tokenOut, address _exchangeSwapAddress) external;
    function changeVITComposition(address[] memory newVITs, uint256[] memory _newAmounts) external;
    function initiateReweight(address[] memory newVITs, uint256[] memory _newAmounts) external;
    function redeemUnderlying(uint256 _numShares, uint256 _tranche) external;
    function getLockupEnd(uint256 _tranche) external view returns (uint256);
    function getTotalUnderlying() external view returns (uint256[] memory);
    function totalUSDCDeposited() external view returns (uint256);
    function getTotalUnderlyingByTranche(uint256 tranche) external view returns (uint256[] memory);
    function vaultData() external view returns (VaultDataTypes.VaultData memory);

    event SvsMinted(address indexed user, uint256 indexed tokenTranche, uint256 indexed numTokens);
    event SvsRedeemed(address indexed user, uint256 indexed tokenTranche, uint256 indexed numTokens);
    event PoolPaused(address admin);
    event PoolUnpaused(address admin);
    function getVITComposition() external view returns(address[] memory VITs, uint256[] memory amounts);
}
