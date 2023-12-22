///SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "./CTokenInterfaces.sol";
import "./TwapGetter.sol";
import "./SafeMath.sol";

// Source: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/GSN/Context.sol
/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with GSN meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
contract Context {
    function _msgSender() internal view returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

// Source: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol
/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// Source: https://github.com/smartcontractkit/chainlink/blob/develop/evm-contracts/src/v0.6/interfaces/AggregatorV3Interface.sol
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);

    function description() external view returns (string memory);

    function version() external view returns (uint256);

    // getRoundData and latestRoundData should both raise "No data present"
    // if they do not have data to report, instead of returning unset values
    // which could be misinterpreted as actual reported values.
    function getRoundData(uint80 _roundId)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

abstract contract PriceOracle {
    /**
     * @notice Get the underlying price of a cToken asset
     * @param cToken The cToken to get the underlying price of
     * @return The underlying asset price mantissa (scaled by 1e18).
     *  Zero means the price is unavailable.
     */
    function getUnderlyingPrice(CTokenInterface cToken)
        external
        virtual
        view
        returns (uint256);
}

contract UniswapV3PriceOracleProxy is Ownable, PriceOracle {
    using SafeMath for uint256;

    /// @notice Indicator that this is a PriceOracle contract (for inspection)
    bool public constant isPriceOracle = true;

    uint16 public constant TWAP_DURATION = 30 minutes;

    TwapGetter public twapGetter;
    address public ethUsdChainlinkAggregatorAddress;

    struct TokenConfig {
        address uniswapV3Pool;
        uint256 chainlinkPriceBase; // 0: Invalid, 1: USD, 2: ETH
        uint256 underlyingTokenDecimals; // e.g. for WBTC/ETH: 8
        uint256 underlyingBaseDecimals; // e.g. for WBTC/ETH: 18
        bool isEthToken0; //ETH-NFD or NFD-ETH?
    }

    mapping(address => TokenConfig) public tokenConfig;

    constructor(address twapGetter_, address ethUsdChainlinkAggregatorAddress_) {
        twapGetter = TwapGetter(twapGetter_);
        ethUsdChainlinkAggregatorAddress = ethUsdChainlinkAggregatorAddress_;
    }

    /**
     * @notice Get the underlying price of a cToken
     * @dev Implements the PriceOracle interface for Compound v2.
     * @param cToken The cToken address for price retrieval
     * @return Price denominated in USD, with 18 decimals, for the given cToken address. Comptroller needs prices in the format: ${raw price} * 1e(36 - baseUnit)
     */
    function getUnderlyingPrice(CTokenInterface cToken) 
        override
        public
        view
        returns (uint256)
    {
        TokenConfig memory config = tokenConfig[address(cToken)];

        uint256 twap = twapGetter.getPriceX96FromSqrtPriceX96(
            twapGetter.getSqrtTwapX96(config.uniswapV3Pool, TWAP_DURATION)
        );

        uint256 underlyingPrice;

        if (config.chainlinkPriceBase == 1) {
            underlyingPrice = uint256(twap)
                .mul(1e36)
                .div(10**config.underlyingBaseDecimals)
                .div(2**96);
        } else if (config.chainlinkPriceBase == 2) { //ETH
            (, int256 ethPriceInUsd, , , ) = AggregatorV3Interface(
                ethUsdChainlinkAggregatorAddress
            )
                .latestRoundData();

            require(ethPriceInUsd > 0, "ETH price invalid");
            if (config.isEthToken0) {
                underlyingPrice = uint256(twap)
                    .mul(uint256(ethPriceInUsd))
                    .mul(1e28) //ethPriceInUsd has 8 decimals
                    .div(10**config.underlyingBaseDecimals)
                    .div(2**96);
            }
            else {
                underlyingPrice = uint(2**96)
                    .mul(uint256(ethPriceInUsd))
                    .mul(1e28) //ethPriceInUsd has 8 decimals
                    .div(10**config.underlyingBaseDecimals)
                    .div(uint256(twap));
            }
        } else {
            revert("Token config invalid");
        }

        require(underlyingPrice > 0, "Underlying price invalid");

        return underlyingPrice;
    }

    function setEthUsdChainlinkAggregatorAddress(address addr)
        external
        onlyOwner
    {
        ethUsdChainlinkAggregatorAddress = addr;
    }

    function setTokenConfigs(
        address[] calldata cTokenAddress,
        address[] calldata uniswapV3PoolAddresss,
        uint256[] calldata chainlinkPriceBase,
        uint256[] calldata underlyingTokenDecimals,
        uint256[] calldata underlyingBaseDecimals,
        bool[] calldata isEthToken0
    ) external onlyOwner {
        require(
            cTokenAddress.length == uniswapV3PoolAddresss.length &&
                cTokenAddress.length == chainlinkPriceBase.length &&
                cTokenAddress.length == underlyingTokenDecimals.length &&
                cTokenAddress.length == underlyingBaseDecimals.length && 
                cTokenAddress.length == isEthToken0.length,
            "Arguments must have same length"
        );

        for (uint256 i = 0; i < cTokenAddress.length; i++) {
            tokenConfig[cTokenAddress[i]] = TokenConfig({
                uniswapV3Pool: uniswapV3PoolAddresss[i],
                chainlinkPriceBase: chainlinkPriceBase[i],
                underlyingTokenDecimals: underlyingTokenDecimals[i],
                underlyingBaseDecimals: underlyingBaseDecimals[i],
                isEthToken0: isEthToken0[i]
            });
            emit TokenConfigUpdated(
                cTokenAddress[i],
                uniswapV3PoolAddresss[i],
                chainlinkPriceBase[i],
                underlyingTokenDecimals[i],
                underlyingBaseDecimals[i],
                isEthToken0[i]
            );
        }
    }

    event TokenConfigUpdated(
        address cTokenAddress,
        address chainlinkAggregatorAddress,
        uint256 chainlinkPriceBase,
        uint256 underlyingTokenDecimals,
        uint256 underlyingBaseDecimals,
        bool isEthToken0
    );
}

