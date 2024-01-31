// ░██████╗████████╗░█████╗░██████╗░██████╗░██╗░░░░░░█████╗░░█████╗░██╗░░██╗
// ██╔════╝╚══██╔══╝██╔══██╗██╔══██╗██╔══██╗██║░░░░░██╔══██╗██╔══██╗██║░██╔╝
// ╚█████╗░░░░██║░░░███████║██████╔╝██████╦╝██║░░░░░██║░░██║██║░░╚═╝█████═╝░
// ░╚═══██╗░░░██║░░░██╔══██║██╔══██╗██╔══██╗██║░░░░░██║░░██║██║░░██╗██╔═██╗░
// ██████╔╝░░░██║░░░██║░░██║██║░░██║██████╦╝███████╗╚█████╔╝╚█████╔╝██║░╚██╗
// ╚═════╝░░░░╚═╝░░░╚═╝░░╚═╝╚═╝░░╚═╝╚═════╝░╚══════╝░╚════╝░░╚════╝░╚═╝░░╚═╝

// SPDX-License-Identifier: MIT
// StarBlock DAO Contracts, https://www.starblockdao.io/

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./IERC721AQueryable.sol";
import "./ERC2981.sol";

import "./wnft_interfaces.sol";

interface IERC721TotalSupply is IERC721 {
    function totalSupply() external view returns (uint256);
}

interface IStarBlockCollection is IERC721AQueryable, IERC2981 {
    struct SaleConfig {
        uint256 startTime;// 0 for not set
        uint256 endTime;// 0 for will not end
        uint256 price;
        uint256 maxAmountPerAddress;// 0 for not limit the amount per address
    }

    event UpdateWhitelistSaleConfig(SaleConfig _whitelistSaleConfig);
    event UpdateWhitelistSaleEndTime(uint256 _oldEndTime, uint256 _newEndTime);
    event UpdateexternalSaleConfig(SaleConfig _externalSaleConfig);
    event UpdateexternalSaleEndTime(uint256 _oldEndTime, uint256 _newEndTime);
    event UpdateChargeToken(IERC20 _chargeToken);

    function supportsInterface(bytes4 _interfaceId) external view override(IERC165, IERC721A) returns (bool);
    
    function maxSupply() external view returns (uint256);
    function exists(uint256 _tokenId) external view returns (bool);
    
    function maxAmountForArtist() external view returns (uint256);
    function artistMinted() external view returns (uint256);

    function chargeToken() external view returns (IERC20);

    // function whitelistSaleConfig() external view returns (SaleConfig memory);
    function whitelistSaleConfig() external view 
            returns (uint256 _startTime, uint256 _endTime, uint256 _price, uint256 _maxAmountPerAddress);
    function whitelist(address _user) external view returns (bool);
    function whitelistAmount() external view returns (uint256);
    function whitelistSaleMinted(address _user) external view returns (uint256);

    // function externalSaleConfig() external view returns (SaleConfig memory);
    function externalSaleConfig() external view 
            returns (uint256 _startTime, uint256 _endTime, uint256 _price, uint256 _maxAmountPerAddress);
    function externalSaleMinted(address _user) external view returns (uint256);

    function userCanMintTotalAmount() external view returns (uint256);

    function whitelistMint(uint256 _amount) external payable;
    function externalMint(uint256 _amount) external payable;
}

interface IHarvestStrategy {
    function canHarvest(uint256 _pid, address _forUser, uint256[] memory _wnfTokenIds) external view returns (bool);
}

interface INFTMasterChef {
    event AddPoolInfo(IERC721Metadata nft, IWrappedNFT wnft, uint256 startBlock,
                    RewardInfo[] rewards, uint256 depositFee, IERC20 dividendToken, bool withUpdate);
    event SetStartBlock(uint256 pid, uint256 startBlock);
    event UpdatePoolReward(uint256 pid, uint256 rewardIndex, uint256 rewardBlock, uint256 rewardForEachBlock, uint256 rewardPerNFTForEachBlock);
    event SetPoolDepositFee(uint256 pid, uint256 depositFee);
    event SetHarvestStrategy(IHarvestStrategy harvestStrategy);
    event SetPoolDividendToken(uint256 pid, IERC20 dividendToken);

    event AddTokenRewardForPool(uint256 pid, uint256 addTokenPerPool, uint256 addTokenPerBlock, bool withTokenTransfer);
    event AddDividendForPool(uint256 pid, uint256 addDividend);

    event UpdateDevAddress(address payable devAddress);
    event EmergencyStop(address user, address to);
    event ClosePool(uint256 pid, address payable to);

    event Deposit(address indexed user, uint256 indexed pid, uint256[] tokenIds);
    event Withdraw(address indexed user, uint256 indexed pid, uint256[] wnfTokenIds);
    event WithdrawWithoutHarvest(address indexed user, uint256 indexed pid, uint256[] wnfTokenIds);
    event Harvest(address indexed user, uint256 indexed pid, uint256[] wnftTokenIds,
                    uint256 mining, uint256 dividend);

    // Info of each NFT.
    struct NFTInfo {
        bool deposited;     // If the NFT is deposited.
        uint256 rewardDebt; // Reward debt.

        uint256 dividendDebt; // Dividend debt.
    }

    //Info of each Reward
    struct RewardInfo {
        uint256 rewardBlock;
        uint256 rewardForEachBlock;    //Reward for each block, can only be set one with rewardPerNFTForEachBlock
        uint256 rewardPerNFTForEachBlock;    //Reward for each block for every NFT, can only be set one with rewardForEachBlock
    }

    // Info of each pool.
    struct PoolInfo {
        IWrappedNFT wnft;// Address of wnft contract.

        uint256 startBlock; // Reward start block.

        uint256 currentRewardIndex;// the current reward phase index for poolsRewardInfos
        uint256 currentRewardEndBlock;  // the current reward end block.

        uint256 amount;     // How many NFTs the pool has.
       
        uint256 lastRewardBlock;  // Last block number that token distribution occurs.
        uint256 accTokenPerShare; // Accumulated tokens per share, times 1e12.
       
        IERC20 dividendToken;
        uint256 accDividendPerShare;

        uint256 depositFee;// ETH charged when user deposit.
    }
   
    function token() external view returns (IERC20);

    function poolLength() external view returns (uint256);
    function poolRewardLength(uint256 _pid) external view returns (uint256);

    function poolInfos(uint256 _pid) external view returns (PoolInfo memory _poolInfo);
    function poolsRewardInfos(uint256 _pid, uint256 _rewardInfoId) external view returns (RewardInfo memory _rewardInfo);
    function poolNFTInfos(uint256 _pid, uint256 _nftTokenId) external view returns (NFTInfo memory _nftInfo);

    function getPoolCurrentReward(uint256 _pid) external view returns (RewardInfo memory _rewardInfo, uint256 _currentRewardIndex);
    function getPoolEndBlock(uint256 _pid) external view returns (uint256 _poolEndBlock);
    function isPoolEnd(uint256 _pid) external view returns (bool);

    function pending(uint256 _pid, uint256[] memory _wnftTokenIds) external view returns (uint256 _mining, uint256 _dividend);
    function deposit(uint256 _pid, uint256[] memory _tokenIds) external payable;
    function withdraw(uint256 _pid, uint256[] memory _wnftTokenIds) external;
    function withdrawWithoutHarvest(uint256 _pid, uint256[] memory _wnftTokenIds) external;
    function harvest(uint256 _pid, address _forUser, uint256[] memory _wnftTokenIds) external returns (uint256 _mining, uint256 _dividend);

    function massUpdatePools() external;
    function updatePool(uint256 _pid) external;
}

interface ITokenPriceUtils {
    function getTokenPrice(address _token) external view returns (uint256);
}

interface INFTPool {
    function nftMasterChef() external view returns (INFTMasterChef);
    function pending(uint256 _pid, uint256[] memory _wnftTokenIds) external view returns (uint256 _mining, uint256 _dividend);
}

interface ICollectionUtils {
    struct CollectionInfo {
        string name;
        string symbol;
        uint256 totalSupply;
        address owner;
    }

    struct TokenInfo {
        string tokenURI;
        address owner;
    }

    function collectionInfos(IERC721Metadata[] memory _nfts) external view returns (CollectionInfo[] memory _collectionInfos);
    function collectionInfo(IERC721Metadata _nft) external view returns (CollectionInfo memory _collectionInfo);

    function tokenInfos(IERC721Metadata _nft, uint256[] memory _tokenIds) external view returns 
            (CollectionInfo memory _collectionInfo, TokenInfo[] memory _tokenInfos);
    function tokenInfosByNfts(IERC721Metadata[] memory _nfts, uint256[] memory _tokenIds) external view returns 
            (CollectionInfo[] memory _collectionInfos, TokenInfo[] memory _tokenInfos);
    function tokenInfo(IERC721Metadata _nft, uint256 _tokenId) external view returns (CollectionInfo memory _collectionInfo, TokenInfo memory _tokenInfo);
    
    //return the token id range the collection may have
    function tokenIdRangeMay(IERC721 _nft) external view returns (uint256 _minTokenId, uint256 _maxTokenId);
    
    //return all the token ids the collection may have
    function allTokenIdsMay(IERC721 _nft) external view returns (uint256[] memory _tokenIds);

    function ownedNFTTokenIds(IERC721 _nft, address _user) external view returns (uint256[] memory _ownedTokenIds);

    function ownedNFTTokenIdsByIdRange(IERC721 _nft, address _user, uint256 _minTokenId, uint256 _maxTokenId) external view returns (uint256[] memory _ownedTokenIds);

    function totalSupplyMay(IERC721 _nft) external view returns (uint256);

    function tokenIdExistsMay(IERC721 _nft, uint256 _tokenId) external view returns (bool);

    //check if NFT is enumerable by itself
    function canEnumerate(IERC721 _nft) external view returns (bool);

    function areContract(address[] memory _accounts) external view returns (bool[] memory);
    function isContract(address _account) external view returns (bool);

    function supportERC721(IERC721 _nft) external view returns (bool);
}

interface INFTMasterChefBatch {
    function nftPool() external view returns (INFTPool);
    function nftMasterChef() external view returns (INFTMasterChef);
    function ownedNFTTokenIds(IERC721 _nft, address _user) external view returns (uint256[] memory _ownedTokenIds);
    function pending(uint256 _pid, uint256[] memory _wnftTokenIds) external view returns (uint256 _mining, uint256 _dividend);
}
