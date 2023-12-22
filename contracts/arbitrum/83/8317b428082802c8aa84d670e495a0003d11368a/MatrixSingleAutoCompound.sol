// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./MatrixStrategyBase.sol";
import "./MatrixSwapHelper.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Pair.sol";
import "./IMasterChef.sol";
import "./xBOOI.sol";
import "./EnumerableSet.sol";
import "./IERC721.sol";

/// @title Base Lp+MasterChef AutoCompound Strategy Framework,
/// all LP strategies will inherit this contract
contract MatrixSingleAutoCompound is MatrixStrategyBase, MatrixSwapHelper {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public poolId;
    address public masterchef;
    address public output;
    address public USDC = 0x04068DA6C83AFCFA0e13ba15A6696662335D5B75;
    address internal constant MAGICATS = 0x2aB5C606a5AA2352f8072B9e2E8A213033e2c4c9;
    address internal constant SPOOKYSWAP_ROUTER = 0xF491e7B69E4244ad4002BC14e878a34207E38c29;
    address internal constant WFTM = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;
    address internal constant SD = 0x412a13C109aC30f0dB80AD3Bd1DeFd5D0A6c0Ac6;
    address internal constant SFTMX = 0xd7028092c830b5C8FcE061Af2E593413EbbC1fc1;
    address internal constant BOO = 0x841FAD6EAe12c286d1Fd18d1d525DFfA75C7EFFE;
    address internal constant XBOO = 0xa48d959AE2E88f1dAA7D5F611E01908106dE7598;

    constructor(
        address _want,
        uint256 _poolId,
        address _masterchef,
        address _output,
        address _uniRouter,
        address _vault,
        address _treasury
    )
        MatrixStrategyBase(_want, _vault, _treasury)
        MatrixSwapHelper(_uniRouter)
    {
        _initialize(_masterchef, _output, _poolId);
    }

    function _initialize(
        address _masterchef,
        address _output,
        uint256 _poolId
    ) internal virtual {
        masterchef = _masterchef;
        output = _output;
        poolId = _poolId;

        _setWhitelistedAddresses();
        _setDefaultSwapPaths();
        _giveAllowances();
    }

    /// @notice Allows strategy governor to setup custom path and dexes for token swaps
    function setSwapPath(
        address _fromToken,
        address _toToken,
        address _unirouter,
        address[] memory _path
    ) external onlyOwner {
        _setSwapPath(_fromToken, _toToken, _unirouter, _path);
    }

    /// @notice Override this to enable other routers or token swap paths
    function _setWhitelistedAddresses() internal virtual {
        whitelistedAddresses.add(unirouter);
        whitelistedAddresses.add(USDC);
        whitelistedAddresses.add(want);
        whitelistedAddresses.add(output);
        whitelistedAddresses.add(wrapped);
        whitelistedAddresses.add(SD);
        whitelistedAddresses.add(BOO);
        whitelistedAddresses.add(SPOOKYSWAP_ROUTER);
        whitelistedAddresses.add(XBOO);
    }

    function _enterXBOO() internal returns (uint256) {
        uint256 _booBalance = IERC20(BOO).balanceOf(address(this));
        xBOOI(XBOO).enter(_booBalance);
        uint256 xbooBalance = IERC20(XBOO).balanceOf(address(this));
        return xbooBalance;
    }
    
    function _exitXBOO() internal returns (uint256) {
        uint256 _xbooBalance = IERC20(XBOO).balanceOf(address(this));
        xBOOI(XBOO).leave(_xbooBalance);
        uint256 _booBalance = IERC20(BOO).balanceOf(address(this));
        return _booBalance;
    }

    function moveMagicatsFromPoolToPool(uint256 _fromPoolId, uint256 _toPoolId) internal {
        uint256[] memory magicatsIds = getStakedMagicats(_fromPoolId);

        if(magicatsIds.length > 0) {
            // unstake from pool
            IMasterChef(masterchef).stakeAndUnstakeMagicats(_fromPoolId, new uint256[](0), magicatsIds);

            // stake to other pool
            IMasterChef(masterchef).stakeAndUnstakeMagicats(_toPoolId, magicatsIds, new uint256[](0));
        }
    }

    function stakeMagicats(uint256[] memory _tokenIds, uint256 _poolId) external onlyOwner {
        uint256[] memory unstake = new uint256[](0);
        IMasterChef(masterchef).stakeAndUnstakeMagicats(_poolId, _tokenIds, unstake);
    }

    function unstakeMagicats(uint256[] memory _tokenIds, uint256 _poolId) external onlyOwner {
        uint256[] memory stake = new uint256[](0);
        IMasterChef(masterchef).stakeAndUnstakeMagicats(_poolId, stake, _tokenIds);
    }

    function transferMagicat(uint256 _tokenId) external onlyOwner {
        IERC721(MAGICATS).transferFrom(address(this), msg.sender, _tokenId);
    }

    function getStakedMagicats(uint256 _poolId) public view returns (uint256[] memory) {
        return IMasterChef(masterchef).getStakedMagicats(_poolId, address(this));
    }

    function changePid(uint256 _pid) external onlyOwner {
        uint256 _oldPoolId = poolId;

        // check if is a valid pid
        uint256 poolLength = IMasterChef(masterchef).poolLength();
        require(_pid < poolLength, "invalid-pool-id");
        poolId = _pid;

        // get the new output
        (address _output,,,,,,,,,,,) = IMasterChef(masterchef).poolInfo(poolId);
        require(_output != address(0), "invalid-pool-output");
        output = _output;

        // whitelist in the matrixswaphelper
        whitelistedAddresses.add(output);

        // give allowances
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(output).safeApprove(unirouter, type(uint256).max);

        // move magicats
        moveMagicatsFromPoolToPool(_oldPoolId, poolId);
    }

    function _setDefaultSwapPaths() internal virtual {
         // BOO -> SD
        address[] memory _booSd = new address[](4);
        _booSd[0] = BOO;
        _booSd[1] = WFTM;
        _booSd[2] = USDC;
        _booSd[3] = SD;
        _setSwapPath(BOO, SD, SPOOKYSWAP_ROUTER, _booSd);

        // SD -> BOO
        address[] memory _sdBOO = new address[](4);
        _sdBOO[0] = SD;
        _sdBOO[1] = USDC;
        _sdBOO[2] = WFTM;
        _sdBOO[3] = BOO;
        _setSwapPath(SD, BOO, SPOOKYSWAP_ROUTER, _sdBOO);

        if (output != wrapped) {
            address[] memory _path = new address[](2);
            _path[0] = output;
            _path[1] = wrapped;
            _setSwapPath(output, wrapped, address(0), _path);
        }
    }

    function _giveAllowances() internal override {
        // approving tokens
        IERC20(want).safeApprove(masterchef, 0);
        IERC20(want).safeApprove(masterchef, type(uint256).max);

        IERC20(XBOO).safeApprove(masterchef, 0);
        IERC20(XBOO).safeApprove(masterchef, type(uint256).max);

    IERC20(output).safeApprove(unirouter, 0);
        IERC20(output).safeApprove(unirouter, type(uint256).max);

        IERC20(BOO).safeApprove(XBOO, 0);
        IERC20(BOO).safeApprove(XBOO, type(uint256).max);

        // approving NFTs
        IERC721(MAGICATS).setApprovalForAll(masterchef, true);
    }

    function _removeAllowances() internal override {
        // removing approval for tokens
        IERC20(want).safeApprove(masterchef, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(BOO).safeApprove(XBOO, 0);

        // removing approval for NFTs
        IERC721(MAGICATS).setApprovalForAll(masterchef, false);
    }

    /// @dev total value managed by strategy is want + want staked in MasterChef
    function totalValue() public view virtual override returns (uint256) {
        (uint256 _totalStaked, ) = IMasterChef(masterchef).userInfo(
            poolId,
            address(this)
        );

        uint256 wantStaked = xBOOI(XBOO).xBOOForBOO(_totalStaked);
        return IERC20(want).balanceOf(address(this)) + wantStaked;
    }

    function _deposit() internal virtual override {
        _enterXBOO();
        uint256 _xbooBalance = IERC20(XBOO).balanceOf(address(this));
        IMasterChef(masterchef).deposit(poolId, _xbooBalance);
    }

    function _beforeWithdraw(uint256 _amout) internal virtual override {
        uint256 _xbooAmount = xBOOI(XBOO).BOOForxBOO(_amout);
        IMasterChef(masterchef).withdraw(poolId, _xbooAmount);
        _exitXBOO();
    }

    function _beforeHarvest() internal virtual {
        IMasterChef(masterchef).deposit(poolId, 0);
    }

    function _harvest()
        internal
        virtual
        override
        returns (uint256 _wantHarvested, uint256 _wrappedFeesAccrued)
    {
        _beforeHarvest();
        uint256 _outputBalance = IERC20(output).balanceOf(address(this));
        if (_outputBalance > 0) {
            if (output != wrapped) {
                _wrappedFeesAccrued = _swap(
                    output,
                    wrapped,
                    (_outputBalance * totalFee) / PERCENT_DIVISOR
                );
                _outputBalance = IERC20(output).balanceOf(address(this));
            } else {
                _wrappedFeesAccrued =
                    (_outputBalance * totalFee) /
                    PERCENT_DIVISOR;
                _outputBalance -= _wrappedFeesAccrued;
            }
            
            // now swapping output to want
            _wantHarvested = _swap(
                    output,
                    want,
                    _outputBalance
            );
        }
    }

    function _beforePanic() internal virtual override {
        IMasterChef(masterchef).emergencyWithdraw(poolId);
        _exitXBOO();
    }

    /// @dev _beforeRetireStrat behaves exactly like _beforePanic hook
    function _beforeRetireStrat() internal override {
        _beforePanic();
    }
}

