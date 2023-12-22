// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

/**
 * @title CASH VaultStorage Contract
 * @notice The VaultStorage contract defines the storage for the Vault contracts
 * @author Stabl Protocol Inc
 */
import "./console.sol";
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {SafeMath} from "./SafeMath.sol";
import {Address} from "./Address.sol";
import {IStrategy} from "./IStrategy.sol";
import {IOracle} from "./IOracle.sol";
import {DUB} from "./DUB.sol";
import "./OwnableUpgradeable.sol";
import "./Helpers.sol";
import {StableMath} from "./StableMath.sol";
import "./IHarvester.sol";

contract VaultStorage is OwnableUpgradeable {
    using SafeMath for uint256;
    using StableMath for uint256;
    using SafeMath for int256;
    using SafeERC20 for IERC20;

    event AssetDefaultStrategyUpdated(address _asset, address _strategy);
    event AssetAllocated(address _asset, address _strategy, uint256 _amount);
    event StrategyApproved(address _addr);
    event StrategyRemoved(address _addr);
    event Mint(address _addr, uint256 _value);
    event Redeem(address _addr, uint256 _value);
    event CapitalPaused();
    event CapitalUnpaused();
    event RebasePaused();
    event RebaseUnpaused();
    event RedeemFeeUpdated(uint256 _redeemFeeBps);
    event AllocateThresholdUpdated(uint256 _threshold);
    event RebaseThresholdUpdated(uint256 _threshold);
    event StrategistUpdated(address _address);
    event MaxSupplyDiffChanged(uint256 maxSupplyDiff);
    event YieldDistribution(address _to, uint256 _yield, uint256 _fee);
    event TrusteeFeeBpsChanged(uint256 _basis);
    event TrusteeAddressChanged(address _address);

    // Registred assets
    mapping(address => bool) internal assets;
    address[] internal allAssets;

    // Additional addresses
    address public harvesterAddress;
    address public priceProvider;

    // Pausing bools
    //  bool public rebasePaused = false;
    //  bool public capitalPaused = true;
    bool public rebasePaused;
    bool public capitalPaused;

    // Fee panel
    address public teamAddress;
    uint256 public teamFeeBps;

    // Mints over this amount automatically rebase. 18 decimals.
    uint256 public rebaseThreshold;

    // Token
    DUB internal dub;

    // Supply control
    uint256 public maxSupplyDiff;

    // Price peg control
    uint256 constant MINT_MINIMUM_ORACLE = 99800000;

    // Base stablecoin
    address public primaryStableAddress;

    // The base strategy index in strategyWithWeights for fast deposit
    uint256 public quickDepositStrategyIndex;

    // All strategies for collateral calcutaions
    address[] internal allStrategies;

    // Array with all strategies and parameters
    StrategyWithWeight[] public strategyWithWeights;

    uint256 public constant TOTAL_WEIGHT = 100000; // 100000 ~ 100%

    // Asset=>array of pool paths
    mapping(address => address[]) internal assetsPoolPaths;

    //  address public swapRouter
    address public swapRouter;

    // Who can call rebase
    mapping(address => bool) public rebaseManagers;

    uint256 constant MAX_UINT =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    uint256 lastRebaseAmount;
    
    uint256 totalRebaseAmount;

    // Strategy base structure
    struct StrategyWithWeight {
        address strategy;
        uint256 minWeight;
        uint256 targetWeight;
        uint256 maxWeight;
        bool enabled;
        bool enabledReward;
    }

    /**
     * @dev Set pool paths batch to specific asset
     * @param _asset Asset address
     * @param _poolPath Pool paths array
     */
    function setAssetsPoolPaths(
        address _asset,
        address[] calldata _poolPath
    ) external onlyOwner {
        _setAssetsPoolPaths(_asset, _poolPath);
    }

    function _setAssetsPoolPaths(
        address _asset,
        address[] calldata _poolPath
    ) internal {
        require(_asset != address(0), "Asset should not be empty.");
        require(_poolPath.length > 0, "Pool Path should not be empty.");
        assetsPoolPaths[_asset] = _poolPath;
    }

    /**
     * @dev Set the Swap Router address
     * @param _swapRouter New Swap Router address
     */
    function setSwapRouter(address _swapRouter) external onlyOwner {
        require(_swapRouter != address(0), "Swap Router should not be empty.");
        swapRouter = _swapRouter;
    }

    /**
     * @dev Set the quick allocate strategy
     * @param _index New quick deposit strategy index
     */
    function setQuickDepositStrategyIndex(uint256 _index) external onlyOwner {
        require(
            _index < strategyWithWeights.length,
            "Index should not be more than strategyWithWeights length."
        );
        quickDepositStrategyIndex = _index;
    }

    /**
     * @dev Set the Primary Stable address
     * @param _primaryStable Address of the Primary Stable
     */
    function setPrimaryStable(address _primaryStable) external onlyOwner {
        require(
            _primaryStable != address(0),
            "PrimaryStable should not be empty."
        );
        primaryStableAddress = _primaryStable;
    }

    /**
     * @dev Sets the maximum allowable difference between
     * total supply and backing assets' value.
     */
    function setMaxSupplyDiff(uint256 _maxSupplyDiff) external onlyOwner {
        maxSupplyDiff = _maxSupplyDiff;
        emit MaxSupplyDiffChanged(_maxSupplyDiff);
    }

    /**
     * @dev Set a minimum amount of CASH in a mint or redeem that triggers a
     * rebase
     * @param _threshold CASH amount with 18 fixed decimals.
     */
    function setRebaseThreshold(uint256 _threshold) external onlyOwner {
        rebaseThreshold = _threshold;
        emit RebaseThresholdUpdated(_threshold);
    }

    /**
     * @dev Check if the sender is a rebase menager
     * @param _sender address of sender
     */
    function isRebaseManager(address _sender) external returns (bool) {
        require(_sender != address(0), "Sender should not be empty.");
        return rebaseManagers[_sender];
    }

    /**
     * @dev Set the Weight against each strategy
     * @param _strategyWithWeights Array of StrategyWithWeight structs to set
     */
    function addStrategyWithWeights(
        StrategyWithWeight calldata _strategyWithWeights
    ) external onlyOwner {
        strategyWithWeights.push(_strategyWithWeights);

        allStrategies.push(_strategyWithWeights.strategy);
    }

    /**
     * @dev Set the Weight against each strategy
     * @param _strategyWithWeights Array of StrategyWithWeight structs to set
     */
    function setStrategyWithWeights(
        uint256 _index,
        StrategyWithWeight calldata _strategyWithWeights
    ) external onlyOwner {
        strategyWithWeights[_index] = _strategyWithWeights;
    }

    /**
     * @dev Set the Harvester address in the Vault
     * @param _harvester Address of Harvester
     */
    function setHarvester(address _harvester) external onlyOwner {
        require(_harvester != address(0), "Empty Harvester Address");
        harvesterAddress = _harvester;
    }

    function setDub(address _dub) external onlyOwner {
        require(_dub != address(0), "Dub should not be empty");
        dub = DUB(_dub);
    }

    /**
     * @dev Set the deposit paused flag to true to prevent capital movement.
     */
    function pauseCapital() external onlyOwner {
        capitalPaused = true;
        emit CapitalPaused();
    }

    /**
     * @dev Set the deposit paused flag to false to enable capital movement.
     */
    function unpauseCapital() external onlyOwner {
        capitalPaused = false;
        emit CapitalUnpaused();
    }

    /**
     * @dev Set rebase managers to allow rebasing to specific external users
     * @param _rebaseManager Candidate for Rebase Manager
     */
    function addRebaseManager(address _rebaseManager) external onlyOwner {
        require(_rebaseManager != address(0), "No Rebase Manager Provided");
        rebaseManagers[_rebaseManager] = true;
    }

    /**
     * @dev Add a supported asset to the contract, i.e. one that can be
     *         to mint CASH.
     * @param _asset Address of asset
     */
    function supportAsset(address _asset) external onlyOwner {
        assets[_asset] = true;
        allAssets.push(_asset);

        IOracle(priceProvider).price(_asset);
    }

    /**
     * @dev Set address of price provider.
     * @param _priceProvider Address of price provider
     */
    function setPriceProvider(address _priceProvider) external onlyOwner {
        require(
            _priceProvider != address(0),
            "PriceProvider should not be empty"
        );
        priceProvider = _priceProvider;
    }

    /**
     * @dev Set the deposit paused flag to true to prevent rebasing.
     */
    function pauseRebase() external onlyOwner {
        rebasePaused = true;
        emit RebasePaused();
    }

    /**
     * @dev Set the deposit paused flag to true to allow rebasing.
     */
    function unpauseRebase() external onlyOwner {
        rebasePaused = false;
        emit RebaseUnpaused();
    }

    /**
    * @dev Set the Fee Distribution Parameters for Vault (currently not used, but may be infuture)
           and for Harvester
    * @param _teamAddress address of the Team account
    * @param _teamFeeBps % in bps which Team would recieve
    */
    function setFeeParams(
        address _teamAddress,
        uint256 _teamFeeBps
    ) external onlyOwner {
        require(_teamAddress != address(0), "TeamAddress should not be empty");
        teamAddress = _teamAddress;
        teamFeeBps = _teamFeeBps;
        IHarvester(harvesterAddress).setTeam(teamAddress, teamFeeBps); ///!!!to be fixed!!!!!!!!!!!!
    }
}

