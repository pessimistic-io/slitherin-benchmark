// SPDX-License-Identifier: AGPL-3.0
/**
 * @notice 
 * Supply controller is intended to return amount of Pana needed to be added/removed 
 * to/from the liquidity pool to move the pana supply in pool closer to the target setting.
 * The treasury then calls the burn and add operations from this 
 * contract to perform the Burn/Supply as determined to maintain the target supply in pool
 *
 * CAUTION: Since the control mechanism is based on a percentage and Pana is an 18 decimal token,
 * any supply of Pana less or equal to 10^^-17 will lead to underflow
 */
pragma solidity ^0.8.10;

import "./SafeERC20.sol";
import "./IERC20Metadata.sol";
import "./IERC20.sol";
import "./IUniswapV2ERC20.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Router02.sol";

import "./PanaAccessControlled.sol";
import "./ISupplyContoller.sol";

abstract contract BaseSupplyController is ISupplyContoller, PanaAccessControlled {
    using SafeERC20 for IERC20;            

    IERC20 internal immutable PANA;
    IERC20 internal immutable TOKEN;

    address public pair; // The LP pair for which this controller will be used
    address public router; // The address of the UniswapV2Router02 router contract for the given pair
    address public supplyControlCaller; // The address of the contract that is responsible for invoking control

    bool public override supplyControlEnabled; // Switch to start/stop supply control at anytime
    bool public override paramsSet; // Flag that indicates whether the params were set for current control regime

    // Loss Ratio, calculated as lossRatio = deltaPS/deltaTS.
    // Where deltaPS = Target Pana Supply in Pool - Current Pana Supply in Pool
    // deltaTS = Increase in total Pana supply
    // Percentage specified to 4 precision digits. 2250 = 22.50% = 0.2250
    uint256 public lossRatio;

    // cf = Channel floor
    // tlr = Target loss ratio
    // Control should take action only when Pana supply in pool at a point falls such that lossRatio < tlr - cf
    // Percentage specified to 4 precision digits. 100 = 1% = 0.01
    uint256 public cf;

    // cc = Channel Ceiling
    // tlr = Target loss ratio
    // Control should take action only when Pana supply in pool at a point grows such that lossRatio > tlr + cc
    // Percentage specified to 4 precision digits. 100 = 1% = 0.01
    uint256 public cc;

    // Minimal time between calculations, seconds
    uint256 public samplingTime;

    // Previous compute time
    uint256 public prev_timestamp;

    modifier supplyControlCallerOnly() {
        require(msg.sender == supplyControlCaller ||
                msg.sender == authority.policy(), 
                "CONTROL: Only invokable by policy or a contract authorized as caller");
        _;
    }

    constructor(
        address _PANA,
        address _pair, 
        address _router, 
        address _supplyControlCaller,
        address _authority
    ) PanaAccessControlled(IPanaAuthority(_authority)) {
        require(_PANA != address(0), "Zero address: PANA");
        require(_pair != address(0), "Zero address: PAIR");
        require(_router != address(0), "Zero address: ROUTER");
        require(_supplyControlCaller != address(0), "Zero address: CALLER");
        require(_authority != address(0), "Zero address: AUTHORITY");

        PANA = IERC20(_PANA);
        TOKEN = (IUniswapV2Pair(_pair).token0() == address(PANA)) ?  
                    IERC20(IUniswapV2Pair(_pair).token1()) : 
                        IERC20(IUniswapV2Pair(_pair).token0());
        pair = _pair;
        router = _router;
        supplyControlCaller = _supplyControlCaller;
        paramsSet = false;
    }

    function enableSupplyControl() external override onlyGovernor {
        require(supplyControlEnabled == false, "CONTROL: Control already in progress");
        require(paramsSet == true, "CONTROL: Control parameters are not set");
        supplyControlEnabled = true;
    }

    function disableSupplyControl() external override onlyGovernor {
        require(supplyControlEnabled == true, "CONTROL: No control in progress");
        supplyControlEnabled = false;
        paramsSet = false; // Control params should be set for new control regime whenever it is started
    }

    function setSupplyControlParams(uint256 _lossRatio, uint256 _cf, uint256 _cc, uint256 _samplingTime) external onlyGovernor {
        uint256 old_lossRatio = paramsSet ? lossRatio : 0;
        uint256 old_cf = paramsSet ? cf : 0;
        uint256 old_cc = paramsSet ? cc : 0;
        uint256 old_samplingTime = paramsSet ? samplingTime : 0; 

        lossRatio = _lossRatio;
        cf = _cf;
        cc = _cc;
        samplingTime = _samplingTime;

        paramsSet = true;

        emit SupplyControlParamsSet(lossRatio, cf, cc, samplingTime, old_lossRatio, old_cf, old_cc, old_samplingTime);
    }

    function compute() external view override returns (uint256 _pana, uint256 _slp, bool _burn) {
        require(paramsSet == true, "CONTROL: Control parameters are not set");

        (_pana, _slp, _burn) = (0, 0, false);

        if (supplyControlEnabled) {
            uint256 _dt = block.timestamp - prev_timestamp;
            if (_dt < samplingTime) {
                // too early for the next control action hence returning zero
                return (_pana, _slp, _burn);
            }

            uint256 _totalSupply = PANA.totalSupply();
            uint256 _panaInPool = getPanaReserves();

            uint256 _targetSupply = lossRatio * _totalSupply / (10**4);
            uint256 _channelFloor = (lossRatio - cf) * _totalSupply / 10**4;
            uint256 _channelCeiling = (lossRatio + cc) * _totalSupply / 10**4;

            if ((_panaInPool < _channelFloor || _panaInPool > _channelCeiling)) {
                int256 panaAmount = computePana(_targetSupply, _panaInPool, _dt);

                _burn = panaAmount < 0;
                if (_burn) {
                    _pana = uint256(-panaAmount);

                    // Burn SLPs containing 1/2 the Pana needed to be burnt. 
                    // Other half will be be burnt through swap                    
                    _slp = (_pana * IUniswapV2Pair(pair).totalSupply()) / (2 * _panaInPool);
                } else {
                    _pana = uint256(panaAmount);
                    _slp = 0;
                }
            }
        }
    }

    function computePana(uint256 _targetSupply, uint256 _panaInPool, uint256 _dt) internal view virtual returns (int256);

    /**
     * @notice burns Pana from the pool using SLP
     * @param _slp uint256 - amount of slp to burn
     */
    function burn(uint256 _slp) external override supplyControlCallerOnly {
        prev_timestamp = block.timestamp;

        IUniswapV2Pair(pair).approve(router, _slp);

        // Half the amount of Pana to burn comes out alongwith the other half in the form of token
        (uint _panaOut, uint _tokenOut) = 
            IUniswapV2Router02(router).removeLiquidity(
                address(PANA),
                address(TOKEN),
                _slp,
                0,
                0,
                address(this),
                type(uint256).max
            );

        TOKEN.approve(router, _tokenOut);

        address[] memory _path = new address[](2);
        _path[0] = address(TOKEN);
        _path[1] = address(PANA);

        // Swap the token to remove the other half
        (uint[] memory _amounts) = IUniswapV2Router02(router).swapExactTokensForTokens(
            _tokenOut, 
            0, 
            _path,
            address(this), 
            type(uint256).max
        );

        // Residual amounts need to be transferred to treasury
        uint256 _panaResidue = _panaOut + _amounts[1];
        uint256 _tokenResidue = _tokenOut - _amounts[0];

        PANA.safeTransfer(msg.sender, _panaResidue);

        if (_tokenResidue > 0) {
            TOKEN.safeTransfer(msg.sender, _tokenResidue);
        }

        emit Burnt(PANA.totalSupply(), getPanaReserves(), _slp, _panaResidue, _tokenResidue);
    }

    /**
     * @notice adds Pana to the pool
     * @param _pana uint256 - amount of pana to add
     */
    function add(uint256 _pana) external override supplyControlCallerOnly {
        prev_timestamp = block.timestamp;

        PANA.approve(router, _pana);

        address[] memory _path = new address[](2);
        _path[0] = address(PANA);
        _path[1] = address(TOKEN);

        // Pana gets added but token gets withdrawn
        (uint[] memory _amounts_1) = IUniswapV2Router02(router).swapExactTokensForTokens(
            _pana / 2, 
            0, 
            _path,
            address(this), 
            type(uint256).max
        );

        TOKEN.approve(router, _amounts_1[1]);

        uint256 _tokForAdd = _amounts_1[1];
        uint256 _panaForAdd = _pana - _amounts_1[0];

        PANA.approve(router, _panaForAdd);

        // Add the other half token amount back to the pool alongwith Pana
        (uint _panaAdded, uint _tokenAdded, uint _slp) = IUniswapV2Router02(router).addLiquidity(
            address(PANA),
            address(TOKEN),
            _panaForAdd,
            _tokForAdd,
            0,
            0,
            address(this),
            type(uint256).max
        );

        uint256 _netPanaAddedToPool = _amounts_1[0] + _panaAdded;

        // Residual amounts need to be transferred to treasury
        uint256 _panaResidue = _panaForAdd - _panaAdded;
        uint256 _tokenResidue = _tokForAdd - _tokenAdded;

        // Transfer SLP to treasury
        IUniswapV2Pair(pair).transfer(msg.sender, _slp);

        PANA.safeTransfer(msg.sender, _panaResidue);
        TOKEN.safeTransfer(msg.sender, _tokenResidue);

        emit Supplied(PANA.totalSupply(), getPanaReserves(), _slp, _netPanaAddedToPool, _panaResidue, _tokenResidue);
    }

    function getPanaReserves() internal view virtual returns(uint256 _reserve) {
        (uint256 _reserve0, uint256 _reserve1, ) = IUniswapV2Pair(pair).getReserves();
        _reserve = (IUniswapV2Pair(pair).token0() == address(PANA)) ? _reserve0 : _reserve1;
    }
}
