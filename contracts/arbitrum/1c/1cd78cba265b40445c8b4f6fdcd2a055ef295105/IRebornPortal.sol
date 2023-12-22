// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {PortalLib} from "./PortalLib.sol";
import {BitMapsUpgradeable} from "./BitMapsUpgradeable.sol";

interface IRebornDefinition {
    struct InnateParams {
        uint256 talentNativePrice;
        uint256 talentDegenPrice;
        uint256 propertyNativePrice;
        uint256 propertyDegenPrice;
    }

    struct ReferParams {
        address parent;
        address grandParent;
    }

    struct SoupParams {
        uint256 soupPrice;
        uint256 charTokenId;
        uint256 deadline;
        bytes32 r;
        bytes32 s;
        uint8 v;
    }

    struct ExhumeParams {
        address exhumee;
        uint256 tokenId;
        uint256 nativeCost;
        uint256 degenCost;
        uint256 shovelTokenId; // if no shovel, tokenId is 0
        uint256 deadline;
        bytes32 r;
        bytes32 s;
        uint8 v;
    }

    struct PermitParams {
        uint256 amount;
        uint256 deadline;
        bytes32 r;
        bytes32 s;
        uint8 v;
    }

    struct LifeDetail {
        bytes32 seed;
        address creator; // ---
        // uint96 max 7*10^28  7*10^10 eth  //   |
        uint96 reward; // ---
        uint96 rebornCost; // ---
        uint16 age; //   |
        uint32 round; //   |
        // uint64 max 1.8*10^19             //   |
        uint64 score; //   |
        uint48 nativeCost; // only with decimal of 10^6 // ---
        string creatorName;
    }

    struct SeasonData {
        mapping(uint256 => PortalLib.Pool) pools;
        /// @dev user address => pool tokenId => Portfolio
        mapping(address => mapping(uint256 => PortalLib.Portfolio)) portfolios;
        uint256 _placeholder;
        uint256 _placeholder2;
        uint256 _placeholder3;
        uint256 _placeholder4;
        uint256 _placeholder5;
        uint256 _jackpot;
    }

    struct AirDropDebt {
        uint128 nativeDebt;
        uint128 degenDebt;
    }

    struct ClaimRewardParams {
        address user;
        uint256 amount;
        uint256 t;
        uint256 deadline;
        bytes32 r;
        bytes32 s;
        uint8 v;
    }

    struct PortalSum {
        bool running;
        uint256 currentSeason;
    }

    event AirdropNative();
    event AirdropDegen();

    event Exhume(
        address indexed exhumer,
        address exhumee,
        uint256 indexed tokenId,
        uint256 indexed shovelTokenId,
        uint256 nonce,
        uint256 nativeCost,
        uint256 degenCost,
        uint256 nativeToJackpot
    );

    enum AirdropVrfType {
        Invalid,
        DropReborn,
        DropNative
    }

    enum TributeDirection {
        Reverse,
        Forward
    }

    struct RequestStatus {
        bool fulfilled; // whether the request has been successfully fulfilled
        bool exists; // whether a requestId exists
        bool executed; // whether the airdrop is executed
        AirdropVrfType t;
        uint256 randomWords; // we only need one random word. keccak256 to generate more
    }

    struct VrfConf {
        bytes32 keyHash;
        uint64 s_subscriptionId;
        uint32 callbackGasLimit;
        uint32 numWords;
        uint16 requestConfirmations;
    }

    struct AirdropConf {
        bool _dropOn; //                  ---
        bool _lockRequestDropReborn;
        bool _lockRequestDropNative;
        uint24 _rebornDropInterval; //        |
        uint24 _nativeDropInterval; //        |
        uint32 _rebornDropLastUpdate; //      |
        uint32 _nativeDropLastUpdate; //      |
        uint120 _placeholder;
    }

    struct EngraveParams {
        uint256 tokenId;
        bytes32 seed;
        uint256 reward;
        uint256 score;
        uint256 age;
        uint256 nativeCost;
        uint256 rebornCost;
        uint256 shovelAmount;
        uint256 charTokenId;
        uint256 recoveredAP;
        string creatorName;
    }

    // define degen reward is odd, native reward is even
    enum RewardToClaimType {
        Invalid,
        EngraveDegen, // 1
        ReferNative, // 2
        ReferDegen // 3
    }

    struct RewardStore {
        uint256 totalReward;
        uint256 rewardDebt;
    }

    event ClaimReward(
        address indexed user,
        RewardToClaimType indexed t,
        uint256 amount
    );

    event ClaimDegenReward(
        address indexed user,
        uint256 indexed nonce,
        uint256 amount,
        uint256 t,
        bytes32 r,
        bytes32 s,
        uint8 v
    );

    event Refer(address referee, address referrer);

    event Incarnate(
        address indexed user,
        uint256 indexed tokenId,
        uint256 indexed charTokenId,
        uint256 talentNativePrice,
        uint256 talentRebornPrice,
        uint256 propertyNativePrice,
        uint256 propertyRebornPrice,
        uint256 soupPrice
    );

    event Engrave(
        bytes32 indexed seed,
        address indexed user,
        uint256 indexed tokenId,
        uint256 score,
        uint256 reward,
        uint256 shovelAmount,
        uint256 startTokenId,
        uint256 charTokenId,
        uint256 recoveredAP
    );

    event Infuse(
        address indexed user,
        uint256 indexed tokenId,
        uint256 amount,
        TributeDirection tributeDirection
    );

    event Baptise(
        address indexed user,
        uint256 amount,
        uint256 indexed baptiseType
    );

    event NewSoupPrice(uint256 price);

    event SwitchPool(
        address indexed user,
        uint256 indexed fromTokenId,
        uint256 indexed toTokenId,
        uint256 fromAmount,
        uint256 reStakeAmount,
        TributeDirection fromDirection,
        TributeDirection toDirection
    );

    /// @dev event about the vault address is set
    event VaultSet(address rewardVault);

    event AirdropVaultSet(address airdropVault);

    event NewSeason(uint256 newSeason);

    event NewIncarnationLimit(uint256 limit);

    event ForgedTo(
        uint256 indexed tokenId,
        uint256 newLevel,
        uint256 burnTokenAmount
    );

    event SetNewPiggyBankFee(uint256 piggyBankFee);

    event ClaimNativeAirdrop(uint256 amount);
    event ClaimDegenAirdrop(uint256 amount);

    event NativeDropRootSet(bytes32, uint256);
    event DegenDropRootSet(bytes32, uint256);

    /// @dev revert when the random seed is duplicated
    error SameSeed();

    /// @dev revert when incarnation count exceed limit
    error IncarnationExceedLimit();

    error InvalidProof();

    error NoRemainingReward();

    error SeasonAlreadyStopped();
}

interface IRebornPortal is IRebornDefinition {
    /**
     * @dev user buy the innate for the life
     * @param innate talent and property choice
     * @param referParams refer params
     */
    function incarnate(
        InnateParams calldata innate,
        ReferParams calldata referParams,
        SoupParams calldata charParams
    ) external payable;

    function incarnate(
        InnateParams calldata innate,
        ReferParams calldata referParams,
        SoupParams calldata charParams,
        PermitParams calldata permitParams
    ) external payable;

    function engrave(EngraveParams calldata engraveParams) external;

    /**
     * @dev reward for share the game
     * @param user user address
     * @param amount amount for reward
     */
    function baptise(
        address user,
        uint256 amount,
        uint256 baptiseType
    ) external;

    /**
     * @dev stake $REBORN on this tombstone
     * @param tokenId tokenId of the life to stake
     * @param amount stake amount, decimal 10^18
     */
    function infuse(
        uint256 tokenId,
        uint256 amount,
        TributeDirection tributeDirection
    ) external;

    /**
     * @dev stake $REBORN with permit
     * @param tokenId tokenId of the life to stake
     * @param amount amount of $REBORN to stake
     */
    function infuse(
        uint256 tokenId,
        uint256 amount,
        TributeDirection tributeDirection,
        PermitParams calldata permitParams
    ) external;

    function switchPool(
        uint256 fromTokenId,
        uint256 toTokenId,
        uint256 amount,
        TributeDirection fromDirection,
        TributeDirection toDirection
    ) external;

    function claimNativeDrops(
        uint256 totalAmount,
        bytes32[] calldata proof
    ) external;

    function claimDegenDrops(
        uint256 totalAmount,
        bytes32[] calldata proof
    ) external;

    /**
     * @dev switch to next season, call by owner
     */
    function toNextSeason() external;

    /**
     * @dev claim reward set by merkle tree
     */
    function claimReward(RewardToClaimType t) external;

    /**
     * @dev claim $DEGEN reward via signer signature
     */
    function claimDegenReward(
        ClaimRewardParams calldata claimRewardParams
    ) external;

    /**
     * @dev get current nonce for claim $DEGEN reward via signature
     */
    function getClaimDegenNonces(address user) external view returns (uint256);
}

