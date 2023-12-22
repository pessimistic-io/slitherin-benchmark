// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./ERC4626.sol";
import "./Ownable.sol";

interface Fees {
	function getDepositFees(address user) external view returns(uint);
	function getWithdrawFees(address user) external view returns(uint);
	function getCompoundFees() external view returns(uint);
}

interface IRewards {
    function compound() external;
    function claimFees() external;
	function signalTransfer(address _receiver) external;
}

interface IGLPRewardRouter {
	function mintAndStakeGlp(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external returns (uint256);
	function handleRewards(
		bool _shouldClaimGmx,
		bool _shouldStakeGmx,
		bool _shouldClaimEsGmx,
		bool _shouldStakeEsGmx,
		bool _shouldStakeMultiplierPoints,
		bool _shouldClaimWeth,
		bool _shouldConvertWethToEth
	) external;
	function signalTransfer(address _receiver) external;
}
interface IGLP is IERC20 {
	function claimable(address _account) external view returns(uint);
}

interface IChainlinkPriceFeed {
    function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
	function decimals() external view returns (uint8);
}

contract voltGLP is ERC4626, Ownable {
    
	uint private constant PRECISION = 1e6;

	IGLPRewardRouter public glpRewardRouter;
	address public treasury;
	IGLP public glp; // Balance
	IGLP public fglp; // Pending Rewards
	IGLP public sGLP; // Transfer
	IRewards public rewards; // Rewards Handler
	IERC20 public weth;
	Fees public feesContract;
	IChainlinkPriceFeed public glpPriceFeed;

	uint public maxGLPDeposits;
	uint public totalGLPDeposited;
	uint public price = 1e18;
	uint public pendingWETH;
	uint public boostedGLP;
	uint public swapSlippage = 4e4; //4%

    constructor(address[] memory glpTokens_, IRewards rewards_, IERC20 weth_, address glpRewardRouter_, address glpManager_, address treasury_, address fees_, string memory name_, string memory symbol_, address glpPriceFeed_) ERC20(name_, symbol_) ERC4626(IERC20(glpTokens_[2])) {		
		fglp = IGLP(glpTokens_[0]);
		glp = IGLP(glpTokens_[1]);
		sGLP = IGLP(glpTokens_[2]);

		glpRewardRouter = IGLPRewardRouter(glpRewardRouter_);
		treasury = treasury_;
		weth = weth_;
		feesContract = Fees(fees_);
		glpPriceFeed = IChainlinkPriceFeed(glpPriceFeed_);
		rewards = rewards_;

		weth.approve(glpManager_, type(uint256).max);
    }

	function deposit(uint256 assets, address receiver) public virtual override returns (uint256) {
		compound();
		assets = sendDepositFees(assets, receiver);

        require(totalAssets() + assets <= maxGLPDeposited(), "Deposits more than max");
        
		uint256 shares = super.deposit(assets, receiver);
		require(shares > 0);

		totalGLPDeposited += assets;
        return shares;
    }

    function mint(uint256 shares, address receiver) public virtual override returns (uint256) {
		compound();

		shares = sendMintFees(shares, receiver);
		uint256 assets = super.mint(shares, receiver);
		totalGLPDeposited += assets;

		require(totalAssets() <= maxGLPDeposited(), "Deposits more than max");

        return assets;
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual override returns (uint256 w) {
		compound();

		assets = sendWithdrawFees(assets, owner);
        w = super.withdraw(assets, receiver, owner);
		totalGLPDeposited -= assets;
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual override returns (uint256 r) {
		compound();
		
		uint256 assets = previewRedeem(shares);
		shares = sendRedeemFees(shares, owner);

        r = super.redeem(shares, receiver, owner);
		totalGLPDeposited -= assets;
    }

	function sendCompoundFees(uint _wethHarvested) internal {
		uint compoundFees = feesContract.getCompoundFees();

		if(compoundFees == 0) return;

		uint fees = _wethHarvested * compoundFees / PRECISION;

		SafeERC20.safeTransfer(weth, treasury, fees);
		pendingWETH -= fees;
	}

	function sendDepositFees(uint assets, address _owner) internal returns(uint) {
		uint depositFees = feesContract.getDepositFees(_owner);

		if(depositFees == 0) return assets;

		uint fees = assets * depositFees / PRECISION;

		SafeERC20.safeTransferFrom(sGLP, _msgSender(), treasury, fees);
		return assets - fees;
	}

	function sendMintFees(uint shares, address _owner) internal returns(uint) {
		uint depositFees = feesContract.getDepositFees(_owner);

		if(depositFees == 0) return shares;

		uint feesShares = shares * depositFees / PRECISION;
		uint fees = super.previewMint(feesShares);

		SafeERC20.safeTransferFrom(sGLP, _msgSender(), treasury, fees);
		return shares - feesShares;
	}

	function sendWithdrawFees(uint assets, address _owner) internal returns(uint) {
		uint withdrawFees = feesContract.getWithdrawFees(_owner);

		if(withdrawFees == 0) return assets;

		uint feesAssets = assets * withdrawFees / PRECISION;
		uint fees = super.previewWithdraw(feesAssets);

		super._transfer(_owner, treasury, fees);
		return assets - feesAssets;
	}

	function sendRedeemFees(uint shares, address _owner) internal returns(uint) {
		uint withdrawFees = feesContract.getWithdrawFees(_owner);

		if(withdrawFees == 0) return shares;

		uint fees = shares * withdrawFees / PRECISION;

		super._transfer(_owner, treasury, fees);
		return shares - fees;
	}

	function compound() public {
		uint balance = glp.balanceOf(address(this)) - totalGLPDeposited;
		if(balance > 0) SafeERC20.safeTransfer(sGLP, treasury, balance);
		if(pendingRewards() + pendingWETH < 1e10) return; //= 0.00000001 WETH

		uint wethBefore = weth.balanceOf(address(this));

		rewards.compound();   // claims and restakes esGMX and mp
        rewards.claimFees();

		uint wethHarvested = weth.balanceOf(address(this)) - wethBefore;
		pendingWETH += wethHarvested;

		sendCompoundFees(wethHarvested);
		swapToGLP();
	}

	function swapToGLP() internal {
		if(pendingWETH < 1e10) return; //= 0.00000001 WETH
		if(totalSupply() == 0) return;

		(,int256 _swapPrice,,,) = glpPriceFeed.latestRoundData();
		uint256 swapPrice = uint256(_swapPrice);
		try glpRewardRouter.mintAndStakeGlp(address(weth), pendingWETH, 0, (pendingWETH * (1e6 - swapSlippage) * (10**glpPriceFeed.decimals())) / (swapPrice * 1e6)) returns (uint256 glpBought) {
			uint totalStaked = glpBought + totalGLPDeposited - boostedGLP;
			price = totalStaked * 1e18 / totalSupply();
			emit Swapped(pendingWETH, swapPrice, price, totalStaked);
			totalGLPDeposited += glpBought;
			pendingWETH = 0;			
		} catch {
			emit SwapFailed(pendingWETH, swapPrice);
		}
	}

	function recoverExceedWETH(address _r) external onlyOwner {
		SafeERC20.safeTransfer(weth, _r, weth.balanceOf(address(this)) - pendingWETH);
	}

	function setFeesContract(address fees_) external onlyOwner {
		feesContract = Fees(fees_);
	}

	function setMaxDeposits(uint maxGLPDeposits_) external onlyOwner {
		maxGLPDeposits = maxGLPDeposits_;
	}

	function setTreasury(address treasury_) external onlyOwner {
		require(treasury_ != address(0), "!address");
		
		treasury = treasury_;
	}

	function setSwapSlippage(uint slippage_) external onlyOwner {
		require(slippage_ <= 1e6, "Wrong slippage");
		swapSlippage = slippage_;
	}

	function setGLPPriceFeed(address glpPriceFeed_) external onlyOwner {
		require(glpPriceFeed_ != address(0), "Wrong address");
		glpPriceFeed = IChainlinkPriceFeed(glpPriceFeed_);
	}

	function totalAssets() public view virtual override returns (uint256) {
		return totalGLPDeposited - boostedGLP;
    } 

	function boostGLP(uint _amount) external onlyOwner {
		SafeERC20.safeTransferFrom(sGLP, _msgSender(), address(this), _amount);
		boostedGLP += _amount;
		totalGLPDeposited += _amount;
	}

	function unboostGLP(uint _amount) external onlyOwner {
		require(_amount <= boostedGLP, "!amount");
		boostedGLP -= _amount;
		totalGLPDeposited -= _amount;
		SafeERC20.safeTransfer(sGLP, _msgSender(), _amount);
	}

	function maxGLPDeposited() internal view returns(uint) {
		return maxGLPDeposits;
	}

	function pendingRewards() public view returns (uint256) {
        return fglp.claimable(address(this));
    }

	//In case of GMX contract changes, suggested by auditor
	function transferEverything(address _new) external onlyOwner {
		rewards.signalTransfer(_new);
	}

	event SwapFailed(uint pendingWETH, uint swapPrice);
	event Swapped(uint pendingWETH, uint swapPrice, uint price, uint totalStaked);
}
