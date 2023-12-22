interface ICore {
    /* ========== Event ========== */
    event MarketSupply(address user, address gToken, uint256 uAmount);
    event MarketRedeem(address user, address gToken, uint256 uAmount);
    function supply(address gToken, uint256 underlyingAmount) external payable returns (uint256);
    function redeemUnderlying(address gToken, uint256 underlyingAmount) external returns (uint256 redeemed);
    function redeemToken(address gToken, uint256 gAmount) external returns (uint256 redeemed);
    function claimGRV() external;
}
