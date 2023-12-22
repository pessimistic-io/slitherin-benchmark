// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "./console.sol";

import "./Ownable.sol";

import {IUniswapV3Factory} from "./IUniswapV3Factory.sol";
import {IERC20, SafeERC20} from "./SafeERC20.sol";
import {EnumerableSet} from "./EnumerableSet.sol";
import {IEnigmaFactory} from "./IEnigmaFactory.sol";

import "./IERC20.sol";

import "./ERC20Sol.sol";
import {Range} from "./EnigmaStructs.sol";
import {IEnigma} from "./IEnigma.sol";

/// @title Enigma base contract containing all Enigma pools storage variables.
// solhint-disable-next-line max-states-count
abstract contract EnigmaStorage is IEnigma, ERC20Sol, Ownable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // #region modifiers
    address public operatorAddress;

    function _onlyOperator() private view {
        require(operatorAddress == msg.sender || owner() == msg.sender, "Enigma: Not Operator or Owner");
    }

    modifier onlyOperator() {
        _onlyOperator();
        _;
    }
    // #end region modifiers

    bytes32 internal _parameters;

    uint256 internal constant PRECISION = 1e18;
    uint256 internal MIN_INITIAL_SHARES = 1e18;

    IUniswapV3Factory public factory;
    IERC20 public token0;
    IERC20 public token1;

    //fee params
    uint256 public constant FEE_LIMIT = 10_000;
    uint256 public SELECTED_FEE = 10_000;
    uint256 public ENIGMA_TREASURY_FEE = 500;
    uint256 public OPERATOR_FEE = SELECTED_FEE - ENIGMA_TREASURY_FEE;

    //storage of the enigma ranges
    Range[] public ranges;
    EnumerableSet.AddressSet internal _pools;

    //limit total supply
    uint256 public maxTotalSupply = 0;
    uint256 deposit0Max;
    uint256 deposit1Max;

    ///is this a private pool
    bool public isPrivate;
    /// list of allowed depositors
    mapping(address => bool) public privateList;

    /// @param _uniFactory Uniswap V3 pool for which liquidity is managed
    function initialize(
        address _uniFactory,
        address _token0,
        address _token1,
        uint24[] calldata _feeTiers,
        uint256 _selectedFee,
        address _owner
    ) external {
        bytes32 parameters = _parameters;
        require(parameters == 0, "Enigma: Pool__AlreadyInitialized");

        require(_uniFactory != address(0), "Enigma: _uniFactory should be non-zero");

        token0 = IERC20(_token0);
        token1 = IERC20(_token1);

        require(address(token0) != address(0));
        require(address(token1) != address(0));

        factory = IUniswapV3Factory(_uniFactory);
        _setSelectedFee(_selectedFee);
        _transferOwnership(_owner);

        //add the pools to the emuarable set
        _addPools(_feeTiers, _token0, _token1);

        /// no cap
        maxTotalSupply = 0;
        deposit0Max = type(uint256).max;
        deposit1Max = type(uint256).max;
    }

    /**
     * @notice Returns the name of the token.
     * @return The name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return "Enigma LP Token";
    }

    /**
     * @notice Returns the symbol of the token, usually a shorter version of the name.
     * @return The symbol of the token.
     */
    function symbol() public view virtual override returns (string memory) {
        return "LP_ENIGMA";
    }

    ///add a new pool to the mapping
    function _addPools(uint24[] calldata feeTiers_, address token0Addr_, address token1Addr_) internal {
        for (uint256 i = 0; i < feeTiers_.length; i++) {
            address pool = factory.getPool(token0Addr_, token1Addr_, feeTiers_[i]);

            require(pool != address(0), "ZA");
            require(!_pools.contains(pool), "P");

            // explicit.
            _pools.add(pool);
        }
    }

    function getPools() external view returns (address[] memory) {
        uint256 len = _pools.length();
        address[] memory output = new address[](len);
        for (uint256 i; i < len; i++) {
            output[i] = _pools.at(i);
        }

        return output;
    }

    /// @param _maxTotalSupply The maximum liquidity token supply the contract allows
    function setMaxTotalSupply(uint256 _maxTotalSupply) external onlyOwner {
        if (maxTotalSupply != _maxTotalSupply) {
            maxTotalSupply = _maxTotalSupply;
            //emit MaxTotalSupplySet(_maxTotalSupply);
        }
        console.log("max total supply set");
    }

    /// @param _deposit0Max The maximum amount of token0 allowed in a deposit
    /// @param _deposit1Max The maximum amount of token1 allowed in a deposit
    function setDepositMax(uint256 _deposit0Max, uint256 _deposit1Max) external onlyOwner {
        if (deposit0Max != _deposit0Max) {
            deposit0Max = _deposit0Max;
        }
        if (deposit1Max != _deposit1Max) {
            deposit1Max = _deposit1Max;
        }
        //emit DepositMaxSet(_deposit0Max, _deposit1Max);
    }

    /// @param listed Array of addresses to be appended
    function appendList(address[] memory listed) external onlyOwner {
        for (uint8 i; i < listed.length; i++) {
            privateList[listed[i]] = true;
        }
    }

    /// @param listed Address of listed to remove
    function removeListed(address listed) external onlyOwner {
        privateList[listed] = false;
    }

    /// @notice Toogle Whitelist configuration
    function togglePrivate() external onlyOwner {
        isPrivate = !isPrivate;
    }

    function setSelectedFee(uint256 _newSelectedFee) public onlyOwner {
        _setSelectedFee(_newSelectedFee);
    }

    function _setSelectedFee(uint256 _newSelectedFee) internal {
        //
        require(_newSelectedFee >= ENIGMA_TREASURY_FEE, "Fee too small");
        require(_newSelectedFee <= FEE_LIMIT, "Fee too large");
        SELECTED_FEE = _newSelectedFee;
        //emit update the fee
    }

    /// @notice set operator address
    /// @param _operator of the enigma pool
    /// @dev only callable by owner or existing operator.
    function setOperator(address _operator) external onlyOperator {
        require(_operator != address(0), "Operator cannot be 0 address");
        operatorAddress = _operator;
    }
}

