// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {FloorToken, ILBFactory} from "./FloorToken.sol";
import {TransferTripleTaxToken} from "./TransferTripleTaxToken.sol";
import {ILBPair} from "./ILBPair.sol";
import {ILBRouter} from "./ILBRouter.sol";
//import {IUniswapV2Pair} from "./lib/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
//import {IUniswapV3Pool} from "./lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {LBRouter} from "./LBRouter.sol";
import {ILBToken} from "./ILBToken.sol";
import {IStrategy} from "./IStrategy.sol";
import {ERC20} from "./TransferTaxToken.sol";
//import {ERC20, IERC20} from "./lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "./IERC20.sol";
//import {ERC20} from "./lib/solmate/src/tokens/ERC20.sol";
import {IStakedVEIN} from "./IStakedVEIN.sol";
//import {StakedVEIN} from "./sVEIN.sol";
//import {VEINvault} from "./GMXstrategy.sol"; //later initialize vault

contract VEIN is FloorToken, TransferTripleTaxToken{

    event Borrow(address indexed user, uint256 ethAmount, uint256 sVeinAmount);
    error AlreadyBorrowed();
    error NoActiveBorrows();
    error HardResetNotEnabled();
    error NotEnoughEthToBorrow();
    error Unauthorized();
    error VaultAlreadySet();

    //hardcoded token addresses
    IERC20 public constant weth =
        IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1); // WETH
    LBRouter public constant router =
        LBRouter(payable(0xb4315e873dBcf96Ffd0acd8EA43f689D8c20fB30)); 

    address public treasury; // treasury address
    address public controller;
    address public strategy;
    address public buyandburn;
     //IStrategy public strat;
    IStakedVEIN public sVein;
    address public vault; // sVein vault address
    address public wethvault;
    address public veinstakersvesting;
    uint256 public gmxethamount;
    uint256 public constant BUY_BURN_FEE = 16;
    uint256 public constant BUY_STAKER_FEE = 16;
    uint256 public constant SELL_BURN_FEE = 16;
    uint256 public constant SELL_STAKER_FEE = 16;
    uint256 public constant TREASURY_FEE = 13;

    uint256 internal constant PRECISION = 1e18;
    uint256 public constant INITIAL_TOTAL_SUPPLY = 60_000_000 * 1e18;
    uint256 public constant VEST_SUPPLY = 150000 * 1e18;

    // Lending & Strategy state

    uint256 public totalBorrowedEth; // total ETH taken out of the floor bin that is owed to the protocol
    mapping(address => uint256) public borrowedEth; // ETH owed to the protocol by each user
    mapping(address => uint256) public sVeinDeposited; // sVein deposited by each user
    mapping(address => bool) public strategyborrow;
    uint256 public borrowedEthlimit;
    uint256 public strategyborrowcap;


    constructor(
        string memory name,
        string memory symbol,
        address owner,
        ILBFactory lbFactory,
        uint24 activeId,
        uint16 binStep,
        uint256 tokenPerBin,
        address _treasury,
        address _controller,
        address _sVault,
        address _veinstakersvesting
    ) FloorToken(weth, lbFactory, activeId, binStep, tokenPerBin) TransferTripleTaxToken(name, symbol, owner) {
        treasury = _treasury;
        controller = _controller;
        //strategy = _strategy;
        strategyborrowcap = 4;
        _mint(_veinstakersvesting, VEST_SUPPLY);
        veinstakersvesting = _veinstakersvesting;
        //vault = _sVault;
        //sVein = new StakedVEIN(address(this), _treasury);
        //setVault(_sVault);
        //_mint(controller, BASE_SUPPLY);

        /* Approvals */
        approve(address(router), type(uint256).max);
        approve(_sVault, type(uint256).max);
        weth.approve(address(router), type(uint256).max);
        ILBToken(address(pair)).approveForAll(address(router), true);
        ILBToken(address(pair)).approveForAll(address(pair), true);

        //setstrategy
        //strat = IStrategy(_strategy);

        //unpauseRebalance();
        //sVein.deposit(1e18, address(0)); //inititialize vault and depositor dead address
    }

    function setVault(address vault_) public {
        if (msg.sender != address(controller)) revert Unauthorized();
        if (vault != address(0)) revert VaultAlreadySet();
        vault = vault_;
        sVein = IStakedVEIN(vault_);
        approve(vault_, type(uint256).max);
    }

    function totalSupply() public view override(ERC20, FloorToken) returns (uint256) {
        return ERC20.totalSupply();
    }

    function balanceOf(address account) public view override(FloorToken, ERC20) returns (uint256) {
        return ERC20.balanceOf(account);
    }

    function _mint(address account, uint256 amount) internal override(FloorToken, ERC20) {
        ERC20._mint(account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual override(ERC20, FloorToken){
        super._burn(account, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override(FloorToken/*, ERC20*/) {
        FloorToken._beforeTokenTransfer(from, to, amount);
    }

        /// -----------------------------------------------------------------------
    /// BORROWING — These are commented because they may change how we calculate floor bin
    /// -----------------------------------------------------------------------

    /// @notice Calculate max borrowable ETH based on sVein balance
    /// @dev    Allows any input amount of sVein, even if higher than total supply.
    ///         Must be gated on frontend.

    function maxBorrowable(
        uint256 sVeinAmount_
    ) public view returns (uint256 untaxed, uint256 taxed) {
        uint256 equivalentVein = sVein.previewRedeem(sVeinAmount_);
        uint256 VeinFloorPrice = floorPrice();
        untaxed = (equivalentVein * VeinFloorPrice) / PRECISION;
        return (untaxed, (untaxed * 95) / 100);
    }

    function testpreview(uint256 _test) public view returns (uint256){
        uint256 we = sVein.previewMint(_test);
        return we;
    }

    function arb(uint256 ethAmountOut_) external view returns(uint256){
            uint256 veinFloorPrice = floorPrice();

            // round up since solidity rounds down
            uint256 veinRequired = (
                ((ethAmountOut_ * PRECISION) / veinFloorPrice)
            ) + 1;
        return veinRequired;
    }

       /// borrow()
    /// -----------------------------------------------------------------------
    /// Pay 5% interest up front, borrow up to max amount of ETH of collateralized
    /// staked Jimbo.

    // Function to borrow ETH against sVein. Can only have one active
    // borrow position at a time.

    function borrow(uint256 ethAmountOut_) external {
        // Check if user has an active borrow
        if (borrowedEth[msg.sender] == 0) {
            // Calculate how much sVein to deposit
            uint256 veinFloorPrice = floorPrice();

            // round up since solidity rounds down
            uint256 veinRequired = (
                ((ethAmountOut_ * PRECISION) / veinFloorPrice)
            ) + 1;

            // 4626 impl should round up when dividing here for share count
            uint256 sVeinToDeposit = sVein.previewMint(veinRequired);

            // Calculate fees and borrow amount
            uint256 stakeFees = (ethAmountOut_ * 17) / 1000;
            uint256 burnFees = (ethAmountOut_ * 17) / 1000;
            uint256 tres = (ethAmountOut_ * 16) / 1000;
            uint256 borrowAmount = (ethAmountOut_ -
                ((ethAmountOut_ * 50) / 1000)) - 1;

            // Adjust internal state
            sVeinDeposited[msg.sender] = sVeinToDeposit;
            borrowedEth[msg.sender] += ethAmountOut_;
            totalBorrowedEth += ethAmountOut_;

            // Deposit from user
            sVein.transferFrom(msg.sender, address(this), sVeinToDeposit);
            //jimbo.setIsRebalancing(true);
            //add unpause rebalancing
            //_removeFloorLiquidity();
            //call rebalance
            //unpauseRebalance();
            _removeLiquidity();

            if (weth.balanceOf(address(this)) < ethAmountOut_)
                revert NotEnoughEthToBorrow();

            // Floor fee remains in contract
            weth.transfer(treasury, tres);
            weth.transfer(msg.sender, borrowAmount);
            //add for staker and buyback
            weth.transfer(treasury, burnFees);
            weth.transfer(wethvault, stakeFees);
            //Remaining weth is transferred to burn contract to buy back and burn vein tokens to dead address
            //you can always lookup burn address
            uint256 getremain = weth.balanceOf(address(this));
            weth.transfer(buyandburn, getremain);
        } else {
            revert AlreadyBorrowed();
        }
    }

    // Repay all borrowed ETH and withdraw uJimbo
    function repayAndWithdraw() external {
        // Check if user has an active borrow
        if (borrowedEth[msg.sender] > 0) {
            // Calculate repayment and adjust internal state
            uint256 ethRepaid = borrowedEth[msg.sender];
            borrowedEth[msg.sender] = 0;
            totalBorrowedEth -= ethRepaid;

            // Return all uJimbo to user
            uint256 sVeinToReturn = sVeinDeposited[msg.sender];
            sVeinDeposited[msg.sender] = 0;

            // Transfer ETH to contract and uJimbo back to user
            weth.transferFrom(msg.sender, buyandburn, ethRepaid);
            sVein.transfer(msg.sender, sVeinToReturn);
        } else {
            revert NoActiveBorrows();
        }
    }
    
    function deploytoGMX() public returns (uint256) {
        //require(strategyborrow[strategy] == true,'Not paid old loan');
        require(msg.sender == controller,'Not controller');
        //pauserebase
        //unpauseRebalance();
        _removeLiquidity();
        uint256 poolethbal  = weth.balanceOf(address(this));
        uint256 newbal = poolethbal / strategyborrowcap;
        //uint amounttovaultperc = strategyborrowcap / 100;
        //uint amounttovault = amounttovaultperc * poolethbal;
        //deposit to vault.. add vault interface
        //gmxethamount = amounttovault;
        weth.transfer(strategy, newbal);

        uint256 getremain = weth.balanceOf(address(this));
        weth.transfer(buyandburn, getremain);
        //strat.enter(newbal, 0);
        //strategy.deposit(){value: amounttovault}
        //if not paid back last borow can't borrow
        //strategyborrow[strategy] == false;
        //addliquidity
        //_deployFloorLiquidity(weth.balanceOf(address(this)));
        //rebalanceFloor();
        return newbal;
    }
    
    /*function repayfromstrategy() public {
        require(strategyborrow[strategy] == false, 'No pool balance in vault');
        require(msg.sender == controller,'Not controller');
        //pauserebase
        strat.withdrawall(0);
        uint256 newbal = weth.balanceOf(address(this));
        uint256 rewardamount = gmxethamount - newbal;
        uint256 stakeFees = (rewardamount * 17) / 1000;
        uint256 burnFees = (rewardamount * 17) / 1000;
        uint256 tres = (rewardamount * 16) / 1000;
        weth.transfer(treasury, tres);
        weth.transfer(treasury, burnFees);
        weth.transfer(wethvault, stakeFees);

        //unpauseRebalance();
        // _deployLiquidity or safedeposit
        strategyborrow[strategy] == true;
        //_deployFloorLiquidity(weth.balanceOf(address(this)));
        //();
    }

    function restrategize() external{
        require(msg.sender == controller,'Not controller');
        repayfromstrategy();
        deploytoGMX();
    }*/

    function changestrategy(address _strategy) external{
        require(msg.sender == controller,'Not controller');
        //strat = IStrategy(_strategy);
        strategy = _strategy;
    } //add onlyowner

    function checkActiveid() public view returns (uint256){
        uint24 activeId = pair.getActiveId();
        return activeId;
    }

    /*function _deployFloorLiquidity(uint256 amount) public {
        (uint24 floorId, uint24 roofId) = range();
        uint24 activeId = pair.getActiveId() + 1;
        uint256 amount1 = weth.balanceOf(address(this));

        int256[] memory deltaIds = new int256[](1);
        uint256[] memory distributionX = new uint256[](1);
        uint256[] memory distributionY = new uint256[](1);

        deltaIds[0] = int256(uint256(uint24((1 << 23) - 1) - activeId));
        distributionX[0] = 0;
        distributionY[0] = 1e18;   

        ILBRouter.LiquidityParameters memory parameter1 = ILBRouter.LiquidityParameters(
            IERC20(address(this)),
            weth,
            100,
            0,
            amount1,
            0,
            0,
            activeId,
            0,
            deltaIds,
            distributionX,
            distributionY,
            address(this),
            address(this),
            block.timestamp + 100
        );

        router.addLiquidity(parameter1);
    }*/

    function _removeLiquidity() internal {
        (uint24 floorId, uint24 roofId) = range();
        uint256 floorBinLiquidityLPBalance = pair.balanceOf(
            address(this),
            floorId //check if correct
        );

        if (floorBinLiquidityLPBalance > 0) {
            uint256[] memory ids = new uint256[](1);
            uint256[] memory amounts = new uint256[](1);

            ids[0] = floorId;
            amounts[0] = floorBinLiquidityLPBalance;

            pair.burn(address(this), address(this), ids, amounts);
        }
    }

        /// @dev Internal function to add liq function
    /*function _addLiquidity(
        int256[] memory deltaIds,
        uint256[] memory distributionX,
        uint256[] memory distributionY,
        uint256 amountX,
        uint256 amountY,
        uint24 activeIdDesired
    ) internal {
        uint256 amountXmin = 0;//(amountX * 99) / 100; // We allow 1% amount slippage
        uint256 amountYmin = (amountY * 99) / 100; // We allow 1% amount slippage

        uint256 idSlippage = activeIdDesired - pair.getActiveId();

        ILBRouter.LiquidityParameters memory liquidityParameters = ILBRouter
            .LiquidityParameters(
                IERC20(address(this)),
                weth,
                binStep,
                /*amountX,
                amountY,
                amountXmin,
                amountYmin,
                activeIdDesired, //activeIdDesired
                idSlippage,
                deltaIds,
                distributionX,
                distributionY,
                address(this),
                address(this),
                block.timestamp + 100
            );

        router.addLiquidity(liquidityParameters);
    }*/

    function setstrategycap(uint256 _cap) external {
        require(msg.sender == controller,'Not controller');
        require(_cap >= 0,'Greater than 30% of pools eth');
        strategyborrowcap = _cap;
    }

    function setController(address _controller) external {
        require(msg.sender == treasury,'Not controller');
        controller = _controller;
    }

    function setWETHVault(address vault_) public {
        require(msg.sender == controller,'Not controller');
        wethvault = vault_;
    }

    function setTreasury(address _treasury) external {
        require(msg.sender == controller,'Not controller');
        treasury = _treasury;
    }

    function setBuyback(address _buyback) external {
        require(msg.sender == controller,'Not controller');
        buyandburn = _buyback;
    }

}
