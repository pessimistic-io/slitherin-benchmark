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

interface GNSVault {
	struct User {
        uint stakedTokens;        // 1e18
        uint debtDai;             // 1e18
        uint stakedNftsCount;
        uint totalBoostTokens;    // 1e18
        uint harvestedRewardsDai; // 1e18
    }

	function harvest() external;
    function stakeTokens(uint amount) external;
    function unstakeTokens(uint amount) external;
	function users(address u) external view returns(User memory);
	function pendingRewardDai() view external returns(uint);
}

interface IGNSPriceProvider {
    function tokenPriceDai() external view returns(uint);
}

contract voltGNS is ERC4626, Ownable {
    
	uint private constant PRECISION = 1e6;

	GNSVault public gnsVault;
	address public treasury;
	Router public gnsRouter;
	uint[] public routerPools;
	IERC20 public gns;
	IERC20 public dai;
	Fees public feesContract;
	IGNSPriceProvider public gnsPriceProvider;

	uint public maxGNSDeposits;
	uint public price = 1e18;
	uint public pendingDAI;
	uint public boostedGNS;
	uint public swapSlippage = 4e4; //4%

    constructor(IERC20 gns_, IERC20 dai_, address gnsVault_, address treasury_, address fees_, string memory name_, string memory symbol_, address gnsPrice_) ERC20(name_, symbol_) ERC4626(gns_) {
		gnsVault = GNSVault(gnsVault_);
		treasury = treasury_;
		gns = gns_;
		dai = dai_;
		feesContract = Fees(fees_);
		gnsPriceProvider = IGNSPriceProvider(gnsPrice_);
    }

	function deposit(uint256 assets, address receiver) public virtual override returns (uint256) {
		compound();
		assets = sendDepositFees(assets);

        require(totalAssets() + assets <= maxGNSDeposited(), "GNS deposits more than max");
        
		uint256 shares = super.deposit(assets, receiver);
		require(shares > 0);
		
		stakeGNS();

        return shares;
    }

    function mint(uint256 shares, address receiver) public virtual override returns (uint256) {
		compound();

		shares = sendMintFees(shares);
		uint256 assets = super.mint(shares, receiver);

		require(totalAssets() <= maxGNSDeposited(), "GNS deposits more than max");

		stakeGNS();

        return assets;
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual override returns (uint256) {
		compound();

		assets = sendWithdrawFees(assets, owner);

		uint gnsBalance = gns.balanceOf(address(this));

		if(gnsBalance < assets) {
			unstakeTokens(assets - gnsBalance);
		}

        return super.withdraw(assets, receiver, owner);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual override returns (uint256) {
		compound();
		
		shares = sendRedeemFees(shares, owner);

        uint256 assets = previewRedeem(shares);
		uint gnsBalance = gns.balanceOf(address(this));

		if(gnsBalance < assets) {
			unstakeTokens(assets - gnsBalance);
		}

        return super.redeem(shares, receiver, owner);
    }

	function sendCompoundFees(uint _daiHarvested) internal {
		uint compoundFees = feesContract.getCompoundFees();

		if(compoundFees == 0) return;

		uint fees = _daiHarvested * compoundFees / PRECISION;

		SafeERC20.safeTransfer(dai, treasury, fees);
		pendingDAI -= fees;
	}

	function sendDepositFees(uint assets) internal returns(uint) {
		uint depositFees = feesContract.getDepositFees(msg.sender);

		if(depositFees == 0) return assets;

		uint fees = assets * depositFees / PRECISION;

		SafeERC20.safeTransferFrom(gns, _msgSender(), treasury, fees);
		return assets - fees;
	}

	function sendMintFees(uint shares) internal returns(uint) {
		uint depositFees = feesContract.getDepositFees(msg.sender);

		if(depositFees == 0) return shares;

		uint feesShares = shares * depositFees / PRECISION;
		uint fees = super.previewMint(feesShares);

		SafeERC20.safeTransferFrom(gns, _msgSender(), treasury, fees);
		return shares - feesShares;
	}

	function sendWithdrawFees(uint assets, address _owner) internal returns(uint) {
		uint withdrawFees = feesContract.getWithdrawFees(msg.sender);

		if(withdrawFees == 0) return assets;

		uint feesAssets = assets * withdrawFees / PRECISION;
		uint fees = super.previewWithdraw(feesAssets);

		super._transfer(_owner, treasury, fees);
		return assets - feesAssets;
	}

	function sendRedeemFees(uint shares, address _owner) internal returns(uint) {
		uint withdrawFees = feesContract.getWithdrawFees(msg.sender);

		if(withdrawFees == 0) return shares;

		uint fees = shares * withdrawFees / PRECISION;

		super._transfer(_owner, treasury, fees);
		return shares - fees;
	}

	function compound() public {
		require(address(gnsRouter) != address(0), "!router");
		if(pendingRewards() + pendingDAI < 1e16) return; //0.01 DAI

		uint daiBefore = dai.balanceOf(address(this));
		gnsVault.harvest();
		uint daiHarvested = dai.balanceOf(address(this)) - daiBefore;
		pendingDAI += daiHarvested;

		sendCompoundFees(daiHarvested);
		swapToGNS();
		stakeGNS();
	}

	function swapToGNS() internal {
		if(pendingDAI < 1e16) return; //0.01 DAI
		if(totalSupply() == 0) return;

		dai.approve(address(gnsRouter), pendingDAI);

		uint swapPrice = gnsPriceProvider.tokenPriceDai();
		(bool success, bytes memory returnData) =
            address(gnsRouter).call( 
                abi.encodePacked( 
                    gnsRouter.uniswapV3Swap.selector, 
                    abi.encode(pendingDAI, (pendingDAI * (1e6 - swapSlippage) * 1e10) / (swapPrice * 1e6), routerPools)
                )
            );

        if (success) { 
            uint256 gnsBought = uint256(bytes32(returnData));
		
			GNSVault.User memory u = gnsVault.users(address(this));
			uint totalStaked = gnsBought + u.stakedTokens - boostedGNS;

			price = totalStaked * 1e18 / totalSupply();
			emit Swapped(pendingDAI, swapPrice, price, totalStaked);
			pendingDAI = 0;
        } else {
            emit SwapFailed(pendingDAI, swapPrice);
        }
	}

	function stakeGNS() internal {
		uint balance = gns.balanceOf(address(this));

		gns.approve(address(gnsVault), balance);
		stakeTokens(balance);
	}

	function stakeTokens(uint _amount) internal {
		gns.approve(address(gnsVault), _amount);

		uint daiBefore = dai.balanceOf(address(this));
		gnsVault.stakeTokens(_amount);
		uint daiHarvested = dai.balanceOf(address(this)) - daiBefore;
		pendingDAI += daiHarvested;

		sendCompoundFees(daiHarvested);
	}

	function unstakeTokens(uint _amount) internal {
		uint daiBefore = dai.balanceOf(address(this));
		gnsVault.unstakeTokens(_amount);
		uint daiHarvested = dai.balanceOf(address(this)) - daiBefore;
		pendingDAI += daiHarvested;

		sendCompoundFees(daiHarvested);
	}

	function recoverExceedDAI(address _r) external onlyOwner {
		SafeERC20.safeTransfer(dai, _r, dai.balanceOf(address(this)) - pendingDAI);
	}

	function setFeesContract(address fees_) external onlyOwner {
		feesContract = Fees(fees_);
	}

	function setMaxDeposits(uint maxGNSDeposits_) external onlyOwner {
		maxGNSDeposits = maxGNSDeposits_;
	}

	function setRouter(address gnsRouter_, uint[] calldata routerPools_) external onlyOwner {
		require(gnsRouter_ != address(0), "!address");

		gnsRouter = Router(gnsRouter_);
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

	function setGNSPriceProvider(address gnsPrice_) external onlyOwner {
		require(gnsPrice_ != address(0), "Wrong address");
		gnsPriceProvider = IGNSPriceProvider(gnsPrice_);
	}

	function totalAssets() public view virtual override returns (uint256) {
        GNSVault.User memory u = gnsVault.users(address(this));
		return u.stakedTokens + gns.balanceOf(address(this)) - boostedGNS;
    } 

	function boostGNS(uint _amount) external onlyOwner {
		SafeERC20.safeTransferFrom(gns, _msgSender(), address(this), _amount);
		boostedGNS += _amount;

		stakeTokens(_amount);
	}

	function unboostGNS(uint _amount) external onlyOwner {
		require(_amount <= boostedGNS, "!amount");

		unstakeTokens(_amount);

		boostedGNS -= _amount;
		SafeERC20.safeTransfer(gns, _msgSender(), _amount);
	}

	function maxGNSDeposited() internal view returns(uint) {
		return maxGNSDeposits;
	}

	function pendingRewards() public view returns (uint256) {
        return gnsVault.pendingRewardDai();
    } 

	event SwapFailed(uint pendingDAI, uint swapPrice);
	event Swapped(uint pendingDAI, uint swapPrice, uint price, uint totalStaked);
}
