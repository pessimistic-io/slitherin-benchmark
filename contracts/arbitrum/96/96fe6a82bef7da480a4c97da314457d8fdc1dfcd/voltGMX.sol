// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./ERC4626.sol";
import "./Ownable.sol";

interface Router {
	function uniswapV3Swap(uint256 amount,uint256 minReturn, uint256[] calldata pools) external;
}

interface Fees {
	function getDepositFees(address user) external view returns(uint);
	function getWithdrawFees(address user) external view returns(uint);
	function getCompoundFees() external view returns(uint);
}

interface IGMXRewardRouter {
	function stakeGmx(uint256 _amount) external;
	function unstakeGmx(uint256 _amount) external;
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
	function claim() external;
	function compound() external;
}
interface IStakedGMX is IERC20 {
	function claimable(address _account) external view returns(uint);
	function claim(address _r) external;
}

interface IChainlinkPriceFeed {
    function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
	function decimals() external view returns (uint8);
}

contract voltGMX is ERC4626, Ownable {
    
	uint private constant PRECISION = 1e6;

	IGMXRewardRouter public gmxRewardRouter;
	IStakedGMX public stakedGmx;
	address public treasury;
	Router public gmxRouter;
	uint[] public routerPools;
	IERC20 public gmx;
	IERC20 public weth;
	Fees public feesContract;
	IChainlinkPriceFeed public gmxPriceFeed;

	uint public maxGMXDeposits;
	uint public price = 1e18;
	uint public pendingWETH;
	uint public boostedGMX;
	uint public swapSlippage = 4e4; //4%

    constructor(IERC20 gmx_, IERC20 weth_, address gmxRewardRouter_, address rewardTracker_, address stakedGmx_, address treasury_, address fees_, string memory name_, string memory symbol_, address gmxPriceFeed_) ERC20(name_, symbol_) ERC4626(gmx_) {
		gmxRewardRouter = IGMXRewardRouter(gmxRewardRouter_);
		stakedGmx = IStakedGMX(stakedGmx_);
		treasury = treasury_;
		gmx = IERC20(gmx_);
		weth = IERC20(weth_);
		feesContract = Fees(fees_);
		gmxPriceFeed = IChainlinkPriceFeed(gmxPriceFeed_);
		stakedGmx.approve(gmxRewardRouter_, type(uint).max);
		gmx.approve(rewardTracker_, type(uint).max);
    }

	function deposit(uint256 assets, address receiver) public virtual override returns (uint256) {
		compound();
		assets = sendDepositFees(assets, receiver);

        require(totalAssets() + assets <= maxGMXDeposited(), "Deposits more than max");
        
		uint256 shares = super.deposit(assets, receiver);
		require(shares > 0);
		
		stakeGMX();

        return shares;
    }

    function mint(uint256 shares, address receiver) public virtual override returns (uint256) {
		compound();

		shares = sendMintFees(shares, receiver);
		uint256 assets = super.mint(shares, receiver);

		require(totalAssets() <= maxGMXDeposited(), "Deposits more than max");

		stakeGMX();

        return assets;
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual override returns (uint256) {
		compound();

		assets = sendWithdrawFees(assets, owner);
		unstakeTokens(assets);

        uint256 shares = super.withdraw(assets, receiver, owner);
		stakeGMX();

		return shares;
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual override returns (uint256) {
		compound();
		
		shares = sendRedeemFees(shares, owner);
        uint256 assets = previewRedeem(shares);
		unstakeTokens(assets);

        assets = super.redeem(shares, receiver, owner);
		stakeGMX();

		return assets;
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

		SafeERC20.safeTransferFrom(gmx, _msgSender(), treasury, fees);
		return assets - fees;
	}

	function sendMintFees(uint shares, address _owner) internal returns(uint) {
		uint depositFees = feesContract.getDepositFees(_owner);

		if(depositFees == 0) return shares;

		uint feesShares = shares * depositFees / PRECISION;
		uint fees = super.previewMint(feesShares);

		SafeERC20.safeTransferFrom(gmx, _msgSender(), treasury, fees);
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
		require(address(gmxRouter) != address(0), "!router");
		uint balance = gmx.balanceOf(address(this));
		if (balance > 0) SafeERC20.safeTransfer(gmx, treasury, gmx.balanceOf(address(this)));

		uint wethBefore = weth.balanceOf(address(this));
		gmxRewardRouter.compound();
		stakedGmx.claim(address(this));
		uint wethHarvested = weth.balanceOf(address(this)) - wethBefore;
		pendingWETH += wethHarvested;

		if(pendingRewards() + pendingWETH < 1e10) return; //0.00000001 WETH

		sendCompoundFees(wethHarvested);
		swapToGMX();
		stakeGMX();
	}

	function swapToGMX() internal {
		if(pendingWETH < 1e10) return; //0.00000001 WETH
		if(totalSupply() == 0) return;

		weth.approve(address(gmxRouter), pendingWETH);

		(,int256 _swapPrice,,,) = gmxPriceFeed.latestRoundData();
		uint256 swapPrice = uint256(_swapPrice);
		(bool success, bytes memory returnData) =
            address(gmxRouter).call( 
                abi.encodePacked( 
                    gmxRouter.uniswapV3Swap.selector,
                    abi.encode(pendingWETH, (pendingWETH * (1e6 - swapSlippage) * (10**gmxPriceFeed.decimals())) / (swapPrice * 1e6), routerPools)
                )
            );

        if (success) { 
            uint256 gmxBought = uint256(bytes32(returnData));
		
			uint totalStaked = gmxBought + stakedGmx.balanceOf(address(this)) - boostedGMX;

			price = totalStaked * 1e18 / totalSupply();
			emit Swapped(pendingWETH, swapPrice, price, totalStaked);
			pendingWETH = 0;
        } else {
            emit SwapFailed(pendingWETH, swapPrice);
        }
	}

	function stakeGMX() internal {
		uint balance = gmx.balanceOf(address(this));
		stakeTokens(balance);
	}

	function stakeTokens(uint _amount) internal {
		uint wethBefore = weth.balanceOf(address(this));
		gmxRewardRouter.stakeGmx(_amount);
		uint wethHarvested = weth.balanceOf(address(this)) - wethBefore;
		pendingWETH += wethHarvested;

		sendCompoundFees(wethHarvested);
	}

	function unstakeTokens(uint _amount) internal {
		uint wethBefore = weth.balanceOf(address(this));
		gmxRewardRouter.unstakeGmx(_amount);
		uint wethHarvested = weth.balanceOf(address(this)) - wethBefore;
		pendingWETH += wethHarvested;

		sendCompoundFees(wethHarvested);
	}

	function recoverExceedWETH(address _r) external onlyOwner {
		SafeERC20.safeTransfer(weth, _r, weth.balanceOf(address(this)) - pendingWETH);
	}

	function setFeesContract(address fees_) external onlyOwner {
		feesContract = Fees(fees_);
	}

	function setMaxDeposits(uint maxGMXDeposits_) external onlyOwner {
		maxGMXDeposits = maxGMXDeposits_;
	}

	function setRouter(address gmxRouter_, uint[] calldata routerPools_) external onlyOwner {
		require(gmxRouter_ != address(0), "!address");

		gmxRouter = Router(gmxRouter_);
		routerPools = routerPools_;
	}

	function setTreasury(address treasury_) external onlyOwner {
		require(treasury_ != address(0), "!address");
		
		treasury = treasury_;
	}

	function setSwapSlippage(uint slippage_) external onlyOwner {
		require(slippage_ <= 1e6, "Wrong slippage");
		swapSlippage = slippage_;
	}

	function setGMXPriceFeed(address gmxPriceFeed_) external onlyOwner {
		require(gmxPriceFeed_ != address(0), "Wrong address");
		gmxPriceFeed = IChainlinkPriceFeed(gmxPriceFeed_);
	}

	function totalAssets() public view virtual override returns (uint256) {
		return stakedGmx.balanceOf(address(this)) + gmx.balanceOf(address(this)) - boostedGMX;
    } 

	function boostGMX(uint _amount) external onlyOwner {
		SafeERC20.safeTransferFrom(gmx, _msgSender(), address(this), _amount);
		boostedGMX += _amount;

		stakeTokens(_amount);
	}

	function unboostGMX(uint _amount) external onlyOwner {
		require(_amount <= boostedGMX, "!amount");

		unstakeTokens(_amount);

		boostedGMX -= _amount;
		SafeERC20.safeTransfer(gmx, _msgSender(), _amount);
	}

	function maxGMXDeposited() internal view returns(uint) {
		return maxGMXDeposits;
	}

	function pendingRewards() public view returns (uint256) {
        return stakedGmx.claimable(address(this));
    } 

	//In case of GMX contract changes, suggested by auditor
	function transferEverything(address _new) external onlyOwner {
		gmxRewardRouter.signalTransfer(_new);
	}

	event SwapFailed(uint pendingWETH, uint swapPrice);
	event Swapped(uint pendingWETH, uint swapPrice, uint price, uint totalStaked);
}

