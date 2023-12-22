interface IGToken {
    function underlyingBalanceOf(address account) external view returns (uint256);
    function exchangeRate() external view returns (uint256);
}
