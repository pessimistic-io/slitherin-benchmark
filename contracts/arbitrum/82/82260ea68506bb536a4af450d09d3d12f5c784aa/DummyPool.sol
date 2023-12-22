// SPDX-License-Identifier: MIT

pragma solidity >0.6.12;
pragma experimental ABIEncoderV2;

import "./SafeMath.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";


contract DummyPool is Ownable, ReentrancyGuard {
    using SafeMath for uint;
    using SafeERC20 for ERC20;

    /* ========== STATE VARIABLES ========== */

    address public collateral;
    address public ArbiTen;
    address public treasury;
    address public _10SHARE;

    address public constant wethAddress = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    uint public lastEpochForMinting = type(uint).max;
    uint public mintingDailyAllowance = 50e18;
    uint public mintedArbiTenSoFarInEpoch = 0;
    uint public mintIncreasePerEpoch = 10e18;

    uint public lastEpochForRedeem = type(uint).max;
    uint public redeemStartEpoch;
    uint public redeemDailyAllowance = 50e18;
    uint public redeemedArbiTenSoFarInEpoch = 0;
    uint public redeemIncreasePerEpoch = 10e18;

    mapping(address => uint) public redeem_share_balances;
    mapping(address => uint) public redeem_collateral_balances;

    uint public unclaimed_pool_collateral;
    uint public unclaimed_pool_share;

    mapping(address => uint) public last_redeemed;

    uint public netMinted;
    uint public netRedeemed;

    // Constants for various precisions
    uint private constant PRICE_PRECISION = 1e18;
    uint private constant COLLATERAL_RATIO_MAX = 1e6;

    // Number of decimals needed to get to 18
    uint private missing_decimals;

    // Pool_ceiling is the total units of collateral that a pool contract can hold
    uint public pool_ceiling = 0;

    // Number of blocks to wait before being able to collectRedemption()
    uint public redemption_delay = 1;

    uint public twapPriceScalingPercentage = 980000; // 98% to start

    // AccessControl state variables
    bool public mint_paused = true;
    bool public redeem_paused = false;
    bool public migrated = false;


    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _ArbiTen,
        address __10SHARE,
        address _collateral,
        address _treasury,
        uint _pool_ceiling,
        uint _redeemStartEpoch
    ) public {

        ArbiTen = _ArbiTen;
        _10SHARE = __10SHARE;
        collateral = _collateral;
        treasury = _treasury;
        pool_ceiling = _pool_ceiling;
        missing_decimals = uint(18).sub(ERC20(_collateral).decimals());

        redeemStartEpoch = _redeemStartEpoch;
    }

    /* ========== VIEWS ========== */

    // Returns ArbiTen value of collateral held in this pool
    function collateralArbiTenBalance() external pure returns (uint) {
        return 0;
    }

    function info()
        external
        view
        returns (
            uint,
            uint,
            uint,
            uint,
            uint,
            bool,
            bool
        )
    {
        return (
            pool_ceiling, // Ceiling of pool - collateral-amount
            ERC20(collateral).balanceOf(address(this)), // amount of COLLATERAL locked in this contract
            unclaimed_pool_collateral, // unclaimed amount of COLLATERAL
            unclaimed_pool_share, // unclaimed amount of SHARE
            getCollateralPrice(), // collateral price
            mint_paused,
            redeem_paused
        );
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    function getCollateralPrice() public pure returns (uint) {
        // only for ETH
        return PRICE_PRECISION;
    }

    function getCollateralToken() external view returns (address) {
        return collateral;
    }

    function netSupplyMinted() external view returns (uint) {
        return ERC20(ArbiTen).balanceOf(0x000000000000000000000000000000000000dEaD);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */


    // Transfer collateral to Treasury to execute strategies
    function transferCollateralToOperator(uint amount) external onlyOwner {
        require(amount > 0, "zeroAmount");
        ERC20(collateral).safeTransfer(msg.sender, amount);
    }
}

