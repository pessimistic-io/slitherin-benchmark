// SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.3;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./SafeMath.sol";
import "./ILiquidityPool.sol";
import "./IComptroller.sol";
import "./IMarket.sol";

/// @title Comptroller Hub Contract
/// @notice Handles the different collateral markets and integrates them with the Liquidity Pool
/// @dev Upgradeable Smart Contract
contract Comptroller is Initializable, OwnableUpgradeable, IComptroller {
    using SafeMath for uint256;

    address public liquidityPool;
    /// @notice Markets registered into this Comptroller
    address[] public markets;
    mapping(address => bool) public isMarket;
    mapping(address => address[]) public borrowerToMarkets;

    uint256 private constant RATIOS = 1e16;
    uint256 private constant FACTOR = 1e18;

    /// @notice Emit new market event
    event AddMarket(address indexed market);
    /// @notice Emit remove market event
    event RemoveMarket(address indexed market);
    /// @notice Emit reset market event
    event ResetMarket();
    /// @notice Emit liquidityPool update event
    event UpdateLiquidityPool(address indexed liquidityPool);

    /// @dev  Helps to perform actions meant to be executed by the Liquidity Pool itself
    modifier onlyLiquidityPool() {
        require(msg.sender == liquidityPool, "Not liquidity pool");
        _;
    }

    modifier onlyMarkets() {
        require(isMarket[msg.sender], "Only markets are allowed to perform this action");
        _;
    }

    /// @notice Upgradeable smart contract constructor
    /// @dev Initializes this comptroller
    function initialize() external initializer {
        __Ownable_init();
    }

    /// @notice Allows the owner to add a new market into the protocol
    /// @param _market (address) Market's address
    function addMarket(address _market) external override onlyOwner {
        require(_market != address(0), "Market shouldn't be zero address");
        require(isMarket[_market] == false, "This market has already added");

        markets.push(_market);
        isMarket[_market] = true;
        emit AddMarket(_market);
    }

    /// @notice Owners can set the Liquidity Pool Address
    /// @param _liquidityPool (address) Liquidity Pool's address
    function setLiquidityPool(address _liquidityPool) external override onlyOwner {
        liquidityPool = _liquidityPool;
        emit UpdateLiquidityPool(_liquidityPool);
    }

    /// @notice Anyone can know how much a borrower can borrow from the Liquidity Pool in USDC terms
    /// @dev Despite the borrower can borrow 100% of this amount, it is recommended to borrow up to 80% to avoid risk of being liquidated
    /// @dev The return value has 18 decimals
    /// @param _borrower (address) Borrower's address
    /// @return capacity (uint256) How much USDC the borrower can borrow from the Liquidity Pool
    function borrowingCapacity(address _borrower) public view override returns (uint256) {
        uint256 capacity = 0;
        address[] memory usedMarkets = borrowerToMarkets[_borrower];
        for (uint256 i = 0; i < usedMarkets.length; i++) {
            if (isMarket[usedMarkets[i]]) {
                capacity = capacity.add(IMarket(usedMarkets[i]).borrowingLimit(_borrower));
            }
        }
        return capacity;
    }

    /// @notice When the collateralize function in Market contract called first time for a user, the market is added to the usedMarket cache
    /// @dev We don't check if the market is duplicated here since when it's only called on the first collaterization
    /// @param _borrower (address) Borrower's address
    /// @param _market (address) Market address
    function addBorrowerMarket(address _borrower, address _market) external override onlyMarkets {
        address[] storage usedMarkets = borrowerToMarkets[_borrower];
        usedMarkets.push(_market);
    }

    /// @notice When user withdraw all the collateral from the market, the market is removed from the usedMarkets cache
    /// @param _borrower (address) Borrower's address
    /// @param _market (address) Market address
    function removeBorrowerMarket(address _borrower, address _market) external override onlyMarkets {
        address[] storage usedMarkets = borrowerToMarkets[_borrower];
        uint256 index = 0;
        for (; index < usedMarkets.length; index++) {
            if (usedMarkets[index] == _market) {
                break;
            }
        }
        uint256 lastIndex = usedMarkets.length - 1;
        usedMarkets[index] = usedMarkets[lastIndex];
        usedMarkets.pop();
    }

    /// @notice Tells how healthy a borrow is
    /// @dev If there is no current borrow 1e18 can be understood as infinite. Healt Ratios greater or equal to 100 are good. Below 100, indicates a borrow can be liquidated
    /// @param _borrower (address) Borrower's address
    /// @return  (uint256) Health Ratio Ex 102 can be understood as 102% or 1.02
    function getHealthRatio(address _borrower) external view override returns (uint256) {
        uint256 currentBorrow = ILiquidityPool(liquidityPool).updatedBorrowBy(_borrower);
        if (currentBorrow == 0) return FACTOR;
        else return borrowingCapacity(_borrower).mul(1e2).div(currentBorrow);
    }

    /// @notice Sends as much collateral as needed to a liquidator that covered a debt on behalf of a borrower
    /// @dev This algorithm decides first on more stable markets (i.e. higher collateral factors), then on more volatile markets, till the amount paid by the liquidator is covered
    /// @dev The amount sent to be covered might not be covered at all. The execution ends on either amount covered or all markets processed
    /// @dev USDC here has nothing to do with the decimals the actual USDC smart contract has. Since it's a market, always assume 18 decimals
    /// @dev This function has a high gas consumption. In any case prefer to use sendCollateralToLiquidatorWithPreference. Use this one on extreme cases.
    /// @param _liquidator (address) Liquidator's address
    /// @param _borrower (address) Borrower's address
    /// @param _amount (uint256) Amount paid by the Liquidator in USDC terms at Liquidity Pool's side
    function sendCollateralToLiquidator(
        address _liquidator,
        address _borrower,
        uint256 _amount
    ) external override onlyLiquidityPool {
        address[] memory localMarkets = markets;
        uint256[] memory borrowingLimits = new uint256[](localMarkets.length);
        uint256[] memory collateralFactors = new uint256[](localMarkets.length);
        uint256 marketsProcessed;

        for (uint256 i = 0; i < localMarkets.length; i++) {
            borrowingLimits[i] = IMarket(localMarkets[i]).borrowingLimit(_borrower);
            collateralFactors[i] = IMarket(localMarkets[i]).getCollateralFactor();
        }

        while (_amount > 0 && marketsProcessed < localMarkets.length) {
            uint256 maxIndex = 0;
            uint256 maxCollateral = 0;
            for (uint256 i = 0; i < localMarkets.length; i++) {
                if (localMarkets[i] != address(0) && borrowingLimits[i] > 0 && collateralFactors[i] > maxCollateral) {
                    maxCollateral = collateralFactors[i];
                    maxIndex = i;
                }
            }

            // in case of all markets has gone through already except the first market, and it has zero borrowing limit
            // maxIndex & maxCollateral keeps zero
            if (maxCollateral > 0) {
                uint256 borrowingLimit = borrowingLimits[maxIndex];
                uint256 collateralFactor = maxCollateral.mul(RATIOS);
                delete localMarkets[maxIndex];
                uint256 collateral = borrowingLimit.mul(FACTOR).div(collateralFactor);
                uint256 toPay = (_amount >= collateral) ? collateral : _amount;
                _amount = _amount.sub(toPay);
                IMarket(markets[maxIndex]).sendCollateralToLiquidator(_liquidator, _borrower, toPay);
            }

            marketsProcessed = marketsProcessed + 1;
        }
    }

    /// @notice Sends as much collateral as needed to a liquidator that covered a debt on behalf of a borrower
    /// @dev Here the Liquidator have to tell the specific order in which they want to get collateral assets
    /// @dev The USDC amount here has 18 decimals
    /// @param _liquidator (address) Liquidator's address
    /// @param _borrower (address) Borrower's address
    /// @param _amount (uint256) Amount paid by the Liquidator in USDC terms at Liquidity Pool's side
    /// @param _markets (address[]) Array of markets in their specific order to send collaterals to the liquidator
    function sendCollateralToLiquidatorWithPreference(
        address _liquidator,
        address _borrower,
        uint256 _amount,
        address[] memory _markets
    ) external override onlyLiquidityPool {
        require(_amount != 0, "Cannot liquidate for 0 amount");
        for (uint256 i = 0; i < _markets.length; i++) {
            if (_amount == 0) break;
            require(isMarket[_markets[i]], "Market is not registered");
            uint256 borrowingLimit = IMarket(_markets[i]).borrowingLimit(_borrower);
            if (borrowingLimit == 0) continue;
            uint256 collateralFactor = IMarket(_markets[i]).getCollateralFactor().mul(RATIOS);
            uint256 collateral = borrowingLimit.mul(FACTOR).div(collateralFactor);
            uint256 toPay = (_amount >= collateral) ? collateral : _amount;
            _amount = _amount.sub(toPay);
            IMarket(_markets[i]).sendCollateralToLiquidator(_liquidator, _borrower, toPay);
        }
    }

    /// @notice Get the addresses of all the markets handled by this comptroller
    /// @return (address[] memory) The array with the addresses of all the markets handled by this comptroller
    function getAllMarkets() public view returns (address[] memory) {
        return markets;
    }

    /// @notice Removes a specific index market from the markets this comptroller handles
    /// @dev The order of markets doesn't matter in this comptroller
    /// @dev This function is executable only by the owner of this comptroller
    function removeMarket(uint256 _index) external onlyOwner {
        require(_index < markets.length, "Invalid market index");

        address market = markets[_index];
        require(isMarket[market] == true, "Market should exist");

        if (_index < markets.length - 1) {
            markets[_index] = markets[markets.length - 1];
        }

        isMarket[market] = false;
        markets.pop();

        emit RemoveMarket(market);
    }
}

