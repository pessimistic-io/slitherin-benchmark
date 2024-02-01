// SPDX-License-Identifier: MIT

// Project: NERD Token
//
// Website: http://nerd.vip
// Twitter: @nerdoneth
//
// Note: The coin is completely useless and intended solely for entertainment and educational purposes. Please do not expect any financial returns.

pragma solidity ^0.8.20;

interface INerd {
    // Airdrop NERD token in constant ratio of 1 ETH = 10 000 NERD
    // Limited to the amount available in contract (excluding staked amounts)
    // Does not airdrop Nerd Sale Right (NERDs)
    // Collected Ether can only be used in the `winnerAddLiquidity` function
    function airdrop() external payable;

    // Stake tokens and withdraw already accumulated staking rewards.
    // Can be called with `amount` = 0.
    function stake(uint256 amount) external;

    // Unstake tokens and withdraw already accumulated staking rewards.
    function unstake(uint256 amount) external;

    // Retrieve the actual accumulated staking reward for a specific owner.
    function stakeRewardOf(address owner) external view returns (uint256 amount);

    // Place an auction bid
    //
    // The auction winner will receive the following benefits:
    // 1) 10% from NERDs auction pool
    // 2) 0.05% of the locked Uniswap LP (main NERD/WETH pool)
    // 3) ability to call `winnerAddLiquidity`, `winnerMintSR` & `winnerBurnSR` until the next auction ends
    function bid(uint256 amount, uint256 deadline) external;

    // Add liquidity to the main NERD/ETH Uniswap pool using contract's ETH balance
    // LP tokens created through this function are forever locked
    // To prevent MEV sandwich attacks, this function will fail if there has been any interaction with the Uniswap pool in the same block.
    // Only the latest auction winner can call this function.
    function winnerAddLiquidity() external;

    // Mint NERDs in exchange for NERD tokens.
    // The exchange ratio is fixed at 10 NERDs = 1 NERD, and the total `amount` is limited to the winning bid amount.
    // Only the latest auction winner can call this function.
    // `amount` - the amount of NERDs to mint
    function winnerMintSR(uint256 amount) external;

    // Burn NERDs in exchange for NERD tokens.
    // The exchange ratio is fixed at 10 NERDs = 1 NERD, and the total `amount` is limited to the winning bid amount.
    // Only the latest auction winner can call this function.
    // `amount` - the amount of NERDs to burn from the wallet.
    function winnerBurnSR(uint256 amount) external;

    // Burn NERDs in exchange for NERD tokens.
    // The exchange ratio is fixed at 40 NERDs = 1 NERD.
    // Unlike `winnerBurnSR`, this method can be called by anyone with an unlimited amount, but it offers a less favorable ratio.
    // `amount` - the amount of NERDs to burn from the wallet.
    function burnSR(uint256 amount) external;

    // Return the address of the Nerd Sale Right (NERDs) contract.
    function SR() external view returns (address);
}

