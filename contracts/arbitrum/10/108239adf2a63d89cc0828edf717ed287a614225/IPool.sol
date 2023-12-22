// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

// import "@openzeppelin/contracts/interfaces/IERC165.sol";

interface IPool {
    // ==============================================================================================
    // Query Function Calls
    // ==============================================================================================
    /// @notice Returns a set of ADDRESSES of the erc20 tokens that are managed by the vault
    /// @return poolTokens array of pool tokens
    function getPoolTokens() external view returns (address[] memory poolTokens);

    /// @notice Returns true if the token is managed 
    /// @param token token address to be checked
    /// @return isPoolToken whether the token address is part of the approved tokens
    function isPoolToken(address token) external view returns (bool isPoolToken);

    /// @notice Returns the tokens managed and amounts of each token managed
    /// @return tokens an array of tokens in the pool
    /// @return values an array of the correspending values in the pool
    function getPoolTokensValue() external view returns (address[] memory tokens, uint256[] memory values);

    // ==============================================================================================
    // Transactional Function Calls
    // ==============================================================================================
    /// @notice Withdraws all tokens to owner
    /// @return tokens Tokens to claim
    /// @return actualTokenAmounts Amounts reclaimed
    function withdrawAll() external returns (address[] memory tokens, uint256[] memory actualTokenAmounts);
}
