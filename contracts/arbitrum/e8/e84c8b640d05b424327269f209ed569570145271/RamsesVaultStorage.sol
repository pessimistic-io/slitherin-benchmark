// SPDX-License-Identifier: MIT
pragma solidity =0.8.18;

import "./IMinter.sol";
import "./IPair.sol";
import "./IVoter.sol";
import "./IGauge.sol";
import "./IRouter.sol";
import "./IVotingEscrow.sol";
import "./IERC20.sol";


abstract contract RamsesVaultStorage {

    struct Deposits {
        uint256 amount0;
        uint256 amount1;
        uint256 liquidity;
        bool onlyLiquidity;
    }

    address public POOL = 0x5513a48F3692Df1d9C793eeaB1349146B2140386;
    IVoter public RAMSES_VOTER = IVoter(0xAAA2564DEb34763E3d05162ed3f5C2658691f499);
    IERC20 public  RAM_TOKEN = IERC20(0xAAA6C1E32C55A7Bfa8066A6FAE9b42650F262418);
    IGauge public  RAMSES_GAUGE = IGauge(0xDBA865F11bb0a9Cd803574eDd782d8B26Ee65767);
    IRouter public  RAMSES_ROUTER = IRouter(0xAAA87963EFeB6f7E0a2711F397663105Acb1805e);
    IVotingEscrow public  RAMSES_VOTING_ESCROW = IVotingEscrow(0xAAA343032aA79eE9a6897Dab03bef967c3289a06);

    uint248 public  PRECISION = 1e18;
    bool public stable;
    
    IPair public lp;
    IERC20 public token0;
    IERC20 public token1;
    uint256 public tokenId;
    address public feeRecipient;
    uint256 public derivedSupply;
    uint256 public MAX_LOCK = 1 weeks;
    uint256 public rewardPerTokenStored;


    mapping(address => Deposits) public deposits;
    mapping(address => uint256) public derivedBalances;
    mapping(address => uint256) public storedRewardsPerUser;
    mapping(address => uint256) public userRewardPerTokenStored;
    

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __cruize_ramese_gap;
}
