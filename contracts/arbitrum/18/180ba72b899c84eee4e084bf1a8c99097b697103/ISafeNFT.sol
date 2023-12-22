// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import "./IERC1155.sol";
//  ____         __       __   ___      _     _
//  /___|  __ _ / _| ___  \ \ / (_) ___| | __| |___
// \___ \ / _` | |_ / _ \  \ V /| |/ _ \ |/ _` / __|
//  ___) | (_| |  _|  __/   | | | |  __/ | (_| \__ \
// |____/ \__,_|_|  \___|   |_| |_|\___|_|\__,_|___/

/// @title  ISafeVault
/// @author crypt0grapher
/// @notice Safe Yield Vault depositing to the third-party yield farms
interface ISafeNFT is IERC1155 {
    enum Tiers {Tier1, Tier2, Tier3, Tier4}

    event TogglePresale(bool _status);

    /**
    *   @notice purchase Safe NFT for exact amount of USD
    *   @param _tier tier of the NFT to purchase which stands for ERC1155 token id [0..3]
    *   @param _amount amount of USD to spend
    *   @param _referral referral getting 5% of the price, should not be the sender, if not specified, goes to treasury
    */
    function buy(Tiers _tier, uint256 _amount, address _referral) external;

    /**
    *   @notice distribute profit among the NFT holders, the function fixes the amount of the reward and the NFT holders and their shares at the moment of the call. It does not transfer the reward to the NFT holders, it just records the amount of the reward for each NFT holder.
    *   @param _amountUSD amount of USD to distribute
    */
    function distributeProfit(uint256 _amountUSD) external;

    /**
    *   @notice the function calculates the amount of the reward for the NFT holder and transfers it to the NFT holder
    */
    function claimReward(Tiers _tier, uint256 _distributionId) external;

    /**
*   @notice the function calculates the amount of the reward for the NFT holder and transfers it to the NFT holder
    */
    function claimRewardsTotal() external;


    /**
    *   @notice gets NFT balance for all tiers
    */
    function getMyBalanceTable() external view returns (uint256[] memory);

    /**
    *   @notice toggles presale status
    */
    function togglePresale() external;

    /**
    *   @notice toggles presale status
    */
    function setPresaleStartDate(uint256 launchDate, uint256 _weekDuration) external;

    /**
    *   @notice sets all discounted NFT prices in USD, for presale for all 4 weeks of the presale
    *   @param _presalePrice 4x4 table of the discounted prices for all 4 tiers for all 4 weeks of the presale
    */
    function setDiscountedPriceTable(uint256[][] memory _presalePrice) external;


    /**
    *   @notice gets NFT balance for all tiers
    */
    function getBalanceTable(address _user) external view returns (uint256[] memory);


    /**
    *   @notice gets NFT price for all tiers in USD
    ///todo in SAFE!
    */
    function getFairPriceTable() external view returns (uint256[] memory);


    /**
    *   @notice gets all NFT prices in USD, the original ones without discounts
    *   @return uint256[] containing all NFT prices in one table in USD
    */
    function getPriceTable() external view returns (uint256[] memory);

    /**
    *   @notice gets all discounted NFT prices in USD, for presale for all 4 weeks of the presale
     *   @return uint256[] containing all NFT prices in one table in USD for the current presale week
    */
    function getDiscountedPriceTable()  external view returns (uint256[] memory);



    /**
    *   @notice gets the current presale week
    *   @return returns 1-4
    */
    function getCurrentPresaleWeek() external view returns (uint256);

    /**
    *   @notice gets NFT price in USD
    *   @return NFT price in USD
    */
    function getPrice(Tiers _tier) external view returns (uint256);


    /**
    *   @notice gets NFT fair price in USD
    *   @return counts not only the sale price but also share of the profit for the tier
    */
    function getFairPrice(Tiers _tier) external view returns (uint256);

    /**
    *   @notice gets the current distribution number
    *   @return current distribution number, the one that assigned to the latest distribution
    */
    function currentDistributionId() external view returns (uint256);

    /**
    *   @notice undistributed profit amount in USD
    *   @return amount of the rewards not yet distributed to NFT holders
    */
    function getUnclaimedRewards() external view returns (uint256);


    /**
    *   @notice returns the amount of the reward share for the NFT holder
    */
    function getMyPendingRewardsTotal() external view returns (uint256);

    /**
    *   @notice returns the amount of the reward share for the NFT holder
    */
    function getPendingRewards(address _user, Tiers _tier, uint256 _distributionId) external view returns (uint256);

    /**
    *   @notice gets the total usd value of the NFT minted
    */
    function getTreasuryCost() external view returns (uint256);
    /**
    *   @notice **Your NFTs (% Treasury) **is calculated in $ as a relation of total price of NFTs possessed by the $ amount of Investment Pool - including its SAFE and USDC components.
    */
    function getMyShareOfTreasury() external view returns (uint256);

}

