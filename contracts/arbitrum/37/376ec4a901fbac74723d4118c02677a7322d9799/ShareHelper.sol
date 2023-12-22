//SPDX-License-Identifier: BSL
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./IRamsesV2Pool.sol";
import "./SafeMath.sol";
import "./FullMath.sol";

import "./OracleLibrary.sol";

library ShareHelper {
    using SafeMath for uint256;

    uint256 public constant DIVISOR = 100e18;

    uint256 public constant FEE_PRECISION = 1e8;

    struct LocalVariables_Inputs {
        IStrategyFactory _factory;
        FeedRegistryInterface _registry;
        IStrategyBase _strategy;
        IRamsesV2Pool _pool;
        uint256 _totalShares;
        uint256 _performanceFeeRate;
        uint256 _protocolPerformanceFee;
    }

    /**
     * @dev Calculates the shares to be given for specific position
     * @param _registry Chainlink registry interface
     * @param _pool The token0
     * @param _isBase Is USD used as base
     * @param _amount0 Amount of token0
     * @param _amount1 Amount of token1
     * @param _totalAmount0 Total amount of token0
     * @param _totalAmount1 Total amount of token1
     * @param _totalShares Total Number of shares
     */
    function calculateShares(
        IStrategyFactory _factory,
        FeedRegistryInterface _registry,
        IRamsesV2Pool _pool,
        bool[2] memory _isBase,
        uint256 _amount0,
        uint256 _amount1,
        uint256 _totalAmount0,
        uint256 _totalAmount1,
        uint256 _totalShares
    ) public view returns (uint256 share) {
        share = _calculateShares(_factory, _registry, _pool, _isBase, _amount0, _amount1, _totalAmount0, _totalAmount1, _totalShares);
    }

    /**
     * @notice Calculates the fee shares from accumulated fees
     * @param _factory Strategy factory address
     * @param _manager Strategy manager contract address
     * @param _accManagementFee Accumulated management fees in terms of shares, decimal 18
     * @param _accPerformanceFee Accumulated performance fee in terms of shares, decimal 18
     * @param _accProtocolPerformanceFee Accumulated performance fee in terms of shares, decimal 18
     */
    function calculateFeeShares(
        IStrategyFactory _factory,
        IStrategyManager _manager,
        uint256 _accManagementFee,
        uint256 _accPerformanceFee,
        uint256 _accProtocolPerformanceFee
    ) public view returns (address managerFeeTo, address protocolFeeTo, uint256 managerShare, uint256 protocolShare) {
        uint256 managementProtocolShare;
        uint256 managementManagerShare;
        uint256 protocolFeeRate = _factory.protocolFeeRate();

        // calculate the fees for protocol and manager from management fees
        if (_accManagementFee > 0) {
            managementProtocolShare = FullMath.mulDiv(_accManagementFee, protocolFeeRate, 1e8);
            managementManagerShare = _accManagementFee.sub(managementProtocolShare);
        }

        // calculate the fees for protocol and manager from performance fees
        if (_accPerformanceFee > 0) {
            protocolShare = FullMath.mulDiv(_accPerformanceFee, protocolFeeRate, 1e8);
            managerShare = _accPerformanceFee.sub(protocolShare);
        }

        managerShare = managementManagerShare.add(managerShare);
        protocolShare = managementProtocolShare.add(protocolShare).add(_accProtocolPerformanceFee);

        // moved here for saving bytecode
        managerFeeTo = _manager.feeTo();
        protocolFeeTo = _factory.feeTo();
    }

    function calculatePerformanceFees(
        IStrategyManager _manager,
        bool[2] memory _isBase,
        uint256 _fee0,
        uint256 _fee1,
        uint256 _totalAmount0,
        uint256 _totalAmount1
    ) public view returns (uint256 _accPerformanceFeeShares, uint256 _accProtocolPerformanceFeeShares) {
        LocalVariables_Inputs memory inputs;

        inputs._factory = _manager.factory();
        inputs._registry = inputs._factory.chainlinkRegistry();
        inputs._strategy = IStrategyBase(_manager.strategy());
        inputs._pool = inputs._strategy.pool();
        inputs._totalShares = IERC20Minimal(address(inputs._strategy)).totalSupply();

        // transfer performance fee to manager
        inputs._performanceFeeRate = _manager.performanceFeeRate();

        // protocol performance fee
        inputs._protocolPerformanceFee = inputs._factory.getProtocolPerformanceFeeRate(address(inputs._pool), address(inputs._strategy));

        // calculate manager performance fees
        if (inputs._performanceFeeRate > 0) {
            _accPerformanceFeeShares = _calculateShares(
                inputs._factory,
                inputs._registry,
                inputs._pool,
                _isBase,
                FullMath.mulDiv(_fee0, inputs._performanceFeeRate, FEE_PRECISION),
                FullMath.mulDiv(_fee1, inputs._performanceFeeRate, FEE_PRECISION),
                _totalAmount0,
                _totalAmount1,
                inputs._totalShares
            );
        }

        // calculate protocol performance fees
        if (inputs._protocolPerformanceFee > 0) {
            _accProtocolPerformanceFeeShares = _calculateShares(
                inputs._factory,
                inputs._registry,
                inputs._pool,
                _isBase,
                FullMath.mulDiv(_fee0, inputs._protocolPerformanceFee, FEE_PRECISION),
                FullMath.mulDiv(_fee1, inputs._protocolPerformanceFee, FEE_PRECISION),
                _totalAmount0,
                _totalAmount1,
                inputs._totalShares
            );
        }
    }

    function _calculateShares(
        IStrategyFactory _factory,
        FeedRegistryInterface _registry,
        IRamsesV2Pool _pool,
        bool[2] memory _isBase,
        uint256 _amount0,
        uint256 _amount1,
        uint256 _totalAmount0,
        uint256 _totalAmount1,
        uint256 _totalShares
    ) internal view returns (uint256 share) {
        address _token0 = _pool.token0();
        address _token1 = _pool.token1();

        _amount0 = OracleLibrary.normalise(_token0, _amount0);
        _amount1 = OracleLibrary.normalise(_token1, _amount1);
        _totalAmount0 = OracleLibrary.normalise(_token0, _totalAmount0);
        _totalAmount1 = OracleLibrary.normalise(_token1, _totalAmount1);

        // price in USD
        uint256 token0Price = OracleLibrary.getPriceInUSD(_factory, _registry, _token0, _isBase[0]);

        uint256 token1Price = OracleLibrary.getPriceInUSD(_factory, _registry, _token1, _isBase[1]);

        if (_totalShares > 0) {
            uint256 numerator = (token0Price.mul(_amount0)).add(token1Price.mul(_amount1));

            uint256 denominator = (token0Price.mul(_totalAmount0)).add(token1Price.mul(_totalAmount1));

            share = FullMath.mulDiv(numerator, _totalShares, denominator);
        } else {
            share = ((token0Price.mul(_amount0)).add(token1Price.mul(_amount1))).div(DIVISOR);
        }
    }
}

