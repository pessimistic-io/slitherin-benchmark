// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.18;

import { ERC20 } from "./ERC20.sol";
import { IERC20 } from "./IERC20.sol";
import { ICamelotFactory } from "./ICamelotFactory.sol";
import { ICamelotRouter } from "./ICamelotRouter.sol";
import { IRacePool } from "./IRacePool.sol";
import { IStakingPool } from "./IStakingPool.sol";


// Camelot does not allow swap directly to the contract address of the token
// So that's why we need this proxy
contract ProxyHolder {
    address public immutable OWNER;

    constructor() {
        OWNER = msg.sender;
    }

    function withdraw(
        address _token
    ) public {
        require(msg.sender == OWNER, "Only owner can withdraw funds");
        uint256 _balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(OWNER, _balance);
    }
}


contract FireDoge is ERC20 {

    bool public isLaunched;
    ProxyHolder public PROXY_HOLDER;

    IERC20 public immutable WETH;
    address public immutable DEX_SWAP_ROUTER;
    address public immutable STAKING_POOL;
    address public immutable RACE_POOL;
    address public immutable DEV;

    uint256 public constant BURN_FEE = 1000;
    uint256 public constant STAKING_FEE = 200;
    uint256 public constant DEV_FEE = 300;
    uint256 public constant RACE_FEE = 500;
    uint256 public constant FEE_DENOMINATOR = 10000;

    uint256 public constant INITAL_MINT_AMOUNT = 1e18 * 1e6;
    address public constant ZERO_ADDRESS = 0x0000000000000000000000000000000000000000;
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    event TaxTaken(
        uint256 burnTax,
        uint256 stakingRewardsTax,
        uint256 raceTax,
        uint256 devTax,
        uint256 actuallyTransfered,
        address sender,
        address recipient
    );

    constructor(
        IERC20 _weth,
        address _dexSwapRouter,
        address _stakingPool,
        address _airdropPool,
        address _racePool,
        address _dev
    ) ERC20("Fire Doge Token", "FIREDOGE") {
        _mint(_airdropPool, INITAL_MINT_AMOUNT);
        WETH = _weth;
        DEX_SWAP_ROUTER = _dexSwapRouter;
        STAKING_POOL = _stakingPool;
        DEV = _dev;
        RACE_POOL = _racePool;
    }

    function deployProxyHolder() public {
        require(address(PROXY_HOLDER) == address(0), "Has been already deployed");
        PROXY_HOLDER = new ProxyHolder();
    }

    function launch() public {
        require(!isLaunched, "Token is already launched");
        isLaunched = true;
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        return _transferWithFeeIfNeccessary(_msgSender(), to, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(sender, spender, amount);
        return _transferWithFeeIfNeccessary(sender, recipient, amount);
    }

    function transferWithoutFee(address to, uint256 amount) public virtual returns (bool) {
        _transfer(_msgSender(), to, amount);
        return true;
    }

    function transferFromWithoutFee(address sender, address recipient, uint256 amount) public virtual returns (bool) {
        address spender = _msgSender();
        _spendAllowance(sender, spender, amount);
        _transfer(sender, recipient, amount);
        return true;
    }

    function _transferWithFeeIfNeccessary(address _sender, address _recipient, uint256 _amount) internal returns (bool) {
        // Happens when this contract perform swaps by itself
        // Do not take fees in this case (otherwise causes recursion)

        if (
            _sender == address(this)
            || _recipient == address(this)
            || !isLaunched
            || _sender == DEV
            || _recipient == DEV
        ) {
            _transfer(_sender, _recipient, _amount);
            return true;
        }

        // 1) Burn this fukcing shitcoin!
        uint256 _burnAmount = _amount * BURN_FEE / FEE_DENOMINATOR;
        _transfer(_sender, DEAD_ADDRESS, _burnAmount);

        // 2) Swap this fukcing shitcoin!
        uint256 _stakingRewardsDogeAmount = _amount * STAKING_FEE / FEE_DENOMINATOR;
        uint256 _devRewardsDogeAmount = _amount * DEV_FEE / FEE_DENOMINATOR;
        uint256 _raceRewardsDogeAmount = _amount * RACE_FEE / FEE_DENOMINATOR;

        address[] memory _swapPath = new address[](2);
        _swapPath[0] = address(this);
        _swapPath[1] = address(WETH);

        uint256 _swapDogeAmount = _stakingRewardsDogeAmount + _devRewardsDogeAmount + _raceRewardsDogeAmount;

        _transfer(_sender, address(this), _swapDogeAmount);
        _approve(address(this), DEX_SWAP_ROUTER, _swapDogeAmount);
        ICamelotRouter(DEX_SWAP_ROUTER)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                _swapDogeAmount,
                0,
                _swapPath,
                address(PROXY_HOLDER),
                DEV,
                block.timestamp
            )
        ;
        PROXY_HOLDER.withdraw(address(WETH));

        // 3) Transfer sweety WETH
        uint256 _totalWethAmount = WETH.balanceOf(address(this));
        uint256 _totalFee = STAKING_FEE + DEV_FEE + RACE_FEE;

        uint256 _stakingWethRewards = _totalWethAmount * (STAKING_FEE * 1e18 /_totalFee) / 1e18;
        uint256 _devWethRewards = _totalWethAmount * (DEV_FEE * 1e18 / _totalFee) / 1e18;
        uint256 _raceWethRewards = _totalWethAmount - _devWethRewards - _stakingWethRewards;

        WETH.transfer(DEV, _devWethRewards);

        WETH.transfer(RACE_POOL, _raceWethRewards);
        IRacePool(RACE_POOL).upsertRacer(_sender, _burnAmount);

        WETH.approve(STAKING_POOL, _stakingWethRewards);
        IStakingPool(STAKING_POOL).injectRewards(_stakingWethRewards);

        // 4) Trasnfer remaining shitcoin amount
        uint256 _transferAmount = _amount - _burnAmount - _swapDogeAmount;
        _transfer(_sender, _recipient, _transferAmount);

        emit TaxTaken(
            _burnAmount,
            _stakingWethRewards,
            _raceWethRewards,
            _devWethRewards,
            _transferAmount,
            _sender,
            _recipient
        );

        return true;
    }

    receive() external payable {}
}

