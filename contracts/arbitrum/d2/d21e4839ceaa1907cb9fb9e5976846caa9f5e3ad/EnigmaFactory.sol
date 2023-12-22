// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./console.sol";

//openzeppelin
import "./Create2.sol";
import "./Ownable.sol";
import "./ERC20.sol";
import {EnumerableSet} from "./EnumerableSet.sol";
//uniswap
import "./IUniswapV3Factory.sol";
import "./IUniswapV3Pool.sol";

//enigma
import "./Enigma.sol";
import "./IEnigmaFactory.sol";
import "./IEnigma.sol";
//import {ImmutableClone} from "./libs/ImmutableClone.sol";

import "./Clones.sol";

/// @title Enigma Factory
/// @notice Next generation liquidity management protocol ontop of Uniswap v3 Factory
/// @author by SteakHut Labs © 2023
contract EnigmaFactory is Ownable, IEnigmaFactory {
    using EnumerableSet for EnumerableSet.AddressSet;

    IUniswapV3Factory private uniswapFactory;

    address private _enigmaImplementation;
    address public enigmaTreasury;

    /// @notice set of all enigma pools ever created
    EnumerableSet.AddressSet private _allEnigmas;
    /// @notice set of enigma pools that have been whitelisted
    EnumerableSet.AddressSet private _whitelist;
    /// @notice set of enigma pools that have been blacklisted
    EnumerableSet.AddressSet private _blacklist;

    //token0 => token1 => creatorAddress
    mapping(address => mapping(address => mapping(address => address))) public enigmaPools;

    /// -----------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------

    ///@notice events shall be contained in the IEnigmaFactory.sol

    /// -----------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------

    constructor(address _uniswapFactory) {
        require(_uniswapFactory != address(0), "_uniswapFactory should be non-zero");
        uniswapFactory = IUniswapV3Factory(_uniswapFactory);
    }

    /// -----------------------------------------------------------
    /// External Functions
    /// -----------------------------------------------------------

    /// @notice deploy enigmaPool
    /// @dev ensure that the fee tiers actually exist
    /// @param _token0 address of token0
    /// @param _token1 address of token0
    /// @param _feeTiers fee tiers to support
    /// @return pool_ implementation of enigmaPool
    function deployEnigmaPool(
        address _token0,
        address _token1,
        uint24[] calldata _feeTiers,
        uint256 _selectedFee,
        bool _isPrivate,
        address _operator
    ) external returns (IEnigma pool_) {
        require(_token0 != address(0) && _token1 != address(0), "Factory: address(0)");
        require(_selectedFee >= 500, "Factory: fee too small");
        require(_feeTiers.length > 0, "Factory: no fee tiers");

        (address token0, address token1) = _sortTokens(_token0, _token1);

        //get the latest implementation
        address implementation = _enigmaImplementation;
        require(implementation != address(0));

        //we should run a check that the pools for feeTiers actually exist
        for (uint256 i; i < _feeTiers.length; i++) {
            address _pool = uniswapFactory.getPool(address(token0), address(token1), uint24(_feeTiers[i]));
            require(_pool != address(0), "Factory: FeeTier does not exist");
        }

        pool_ = IEnigma(
            Clones.cloneDeterministic(
                implementation,
                //abi.encodePacked(_token0, _token1, block.timestamp, msg.sender),
                keccak256(abi.encode(_token0, _token1, block.timestamp, msg.sender))
            )
        );

        Enigma(address(pool_)).initialize(
            address(uniswapFactory), token0, token1, _feeTiers, _selectedFee, msg.sender, _isPrivate, _operator
        );

        //token0 => token1 => creatorAddress
        enigmaPools[token0][token1][msg.sender] = address(pool_);

        //push new enigma pool to the _allEnigmas set
        _allEnigmas.add(address(pool_));

        emit EnigmaCreated(address(pool_));
        return (pool_);
    }

    /// -----------------------------------------------------------
    /// View Functions
    /// -----------------------------------------------------------

    /// @notice Get the address of the LBPair implementation
    /// @return enigmaImplementation
    function getEnigmaImplementation() external view returns (address enigmaImplementation) {
        return _enigmaImplementation;
    }

    /// @notice Private view function to sort 2 tokens in ascending order
    /// @param tokenX The first token
    /// @param tokenY The second token
    /// @return token0 The sorted first token
    /// @return token1 The sorted second token
    function _sortTokens(address tokenX, address tokenY) internal pure returns (address token0, address token1) {
        require(tokenX != tokenY, "same token");
        (token0, token1) = tokenX < tokenY ? (tokenX, tokenY) : (tokenY, tokenX);
        require(token0 != address(0), "no address zero");
    }

    /// -----------------------------------------------------------
    /// Owner Functions
    /// -----------------------------------------------------------

    /// @notice Set the LBPair implementation address
    /// @dev Needs to be called by the owner
    /// @param newEnigmaImplementation The address of the implementation
    function setEnigmaImplementation(address newEnigmaImplementation) external onlyOwner {
        //cannot set the new implementation unless the factory is correct
        if (IEnigma(newEnigmaImplementation).getFactory() != address(this)) {
            revert EnigmaFactory__EnigmaPoolSafetyCheckFailed(newEnigmaImplementation);
        }

        address oldEnigmaImplementation = _enigmaImplementation;
        if (oldEnigmaImplementation == newEnigmaImplementation) {
            revert EnigaFactory__SameImplementation(newEnigmaImplementation);
        }

        _enigmaImplementation = newEnigmaImplementation;

        emit EnigmaImplementationSet(oldEnigmaImplementation, newEnigmaImplementation);
    }

    /// @notice Internal function to set the recipient of the fee
    /// @param feeRecipient The address of the fee recipient
    function setFeeRecipient(address feeRecipient) external onlyOwner {
        if (feeRecipient == address(0)) revert EnigmaFactory__AddressZero();

        address oldFeeRecipient = enigmaTreasury;
        if (oldFeeRecipient == feeRecipient) revert EnigmaFactory__SameFeeRecipient(feeRecipient);

        enigmaTreasury = feeRecipient;
        emit FeeRecipientSet(oldFeeRecipient, feeRecipient);
    }

    /// -----------------------------------------------------------
    /// All Enigmas Functions / Whitelisting Functions
    /// -----------------------------------------------------------

    /// @notice Returns the enigma pool at index specified
    /// @param _index The position index
    /// @return enigmaAddress The addres of the enigmaPool at index `_index`
    function enigmaAtIndex(uint256 _index) public view returns (address enigmaAddress) {
        return _allEnigmas.at(_index);
    }

    /// @notice Returns the number of enigmas created
    /// @return uint256 The number of non-zero balances of strategy
    function enigmaPositionNumber() public view returns (uint256) {
        return _allEnigmas.length();
    }

    /// @notice Returns the enigma pool at index specified
    /// @param _index The position index
    /// @return enigmaAddress The addres of the enigmaPool at index `_index`
    function whitelistAtIndex(uint256 _index) public view returns (address enigmaAddress) {
        return _whitelist.at(_index);
    }

    /// @notice Returns the number of enigmas whitelisted
    /// @return uint256 The number of whitelisted pools
    function whitelistPositionNumber() public view returns (uint256) {
        return _whitelist.length();
    }

    /// @notice whitelist an enigmaPool
    /// @param _enigmaAddress to whitelist/remove
    /// @param isWhitelisted should the pool be whitelisted
    function whitelistEnigma(address _enigmaAddress, bool isWhitelisted) public onlyOwner {
        if (isWhitelisted) {
            _whitelist.add(_enigmaAddress);
        } else {
            _whitelist.remove(_enigmaAddress);
        }
        //emit an event
        emit Whitelist(_enigmaAddress, isWhitelisted);
    }

    /// @notice Returns the enigmaPool at index specified
    /// @param _index The position index
    /// @return enigmaAddress The addres of the enigmaPool at index `_index`
    function blacklistAtIndex(uint256 _index) public view returns (address enigmaAddress) {
        return _blacklist.at(_index);
    }

    /// @notice Returns the number of enigmas blacklisted
    /// @return uint256 The number blacklisted
    function blacklistPositionNumber() public view returns (uint256) {
        return _blacklist.length();
    }

    /// @notice isBlacklisted an enigmaPool
    /// @param _enigmaAddress to whitelist/remove
    /// @param isBlacklisted should the pool be isBlacklisted
    function blacklistEnigma(address _enigmaAddress, bool isBlacklisted) public onlyOwner {
        if (isBlacklisted) {
            _blacklist.add(_enigmaAddress);
        } else {
            _blacklist.remove(_enigmaAddress);
        }
        //emit an event
        emit Blacklist(_enigmaAddress, isBlacklisted);
    }

    /// -----------------------------------------------------------
    /// END Enigma Factory by SteakHut Labs 2023
    /// -----------------------------------------------------------
}

