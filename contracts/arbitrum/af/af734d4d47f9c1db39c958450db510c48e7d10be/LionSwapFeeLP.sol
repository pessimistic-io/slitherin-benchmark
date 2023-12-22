// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./SafeERC20.sol";
import "./IFeeLP.sol";
import "./EnumerableSet.sol";
import "./SafeMath.sol";
import "./IVault.sol";

import "./IReferral.sol";

interface IUniswapOracleV3 {
    function getSqrtTWAP(
        address[] calldata tokens,
        uint24[] calldata fee,
        uint32 twapInterval
    ) external view returns (uint price);
}

contract LionSwapFeeLP {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    bool public isInitialized = false;
    address public owner;
    IERC20 public LionToken;
    IERC20 public esLionToken;
    IERC20 public LPToken;
    IERC20 public usdc;
    IERC20 public weth;
    IFeeLP public feeLP;
    IVault public vault;
    IUniswapOracleV3 public uinswapOracleV3;
    IReferral public referral;
    uint24[] public pairFees;
    address public teamAddress;
    address public vestAddress;
    address public earnAddress;
    uint256 public toTeamRatio;
    mapping(uint256 => uint256) public discountLevel;

    uint256 public BasePoint;
    event Swap(
        address user,
        IERC20 buyToken,
        uint256 LPAmount,
        uint256 needLion,
        uint256 feeLPAmount
    );

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    modifier onlyOwner() {
        require(owner == msg.sender, "LionSwapFeeLP: not owner");
        _;
    }

    function initialize(
        IERC20 _usdc,
        IERC20 _LionToken,
        IERC20 _esLionToken,
        IERC20 _LPToken,
        IERC20 _weth,
        IFeeLP _feeLP,
        IVault _vault,
        IUniswapOracleV3 _uinswapOracleV3,
        uint24[] memory _pairFees,
        IReferral _referral
    ) public {
        require(!isInitialized, "LionSwapFeeLP: already initialized");
        isInitialized = true;
        owner = msg.sender;

        usdc = _usdc;
        weth = _weth;
        LionToken = _LionToken;
        esLionToken = _esLionToken;
        LPToken = _LPToken;
        feeLP = _feeLP;
        vault = _vault;
        uinswapOracleV3 = _uinswapOracleV3;
        pairFees = _pairFees;

        discountLevel[100e18] = 7e3;
        discountLevel[200e18] = 6e3;
        discountLevel[500e18] = 5e3;
        discountLevel[1000e18] = 4e3;
        discountLevel[2000e18] = 3e3;
        discountLevel[5000e18] = 2e3;
        discountLevel[10000e18] = 1e3;
        BasePoint = 1e4;
        referral = _referral;
    }

    function swap(IERC20 buyToken, uint256 LPAmount, uint256 maxLion) public {
        require(discountLevel[LPAmount] > 0, "LionSwapFeeLP: invalid level");
        require(
            buyToken == LionToken || buyToken == esLionToken,
            "LionSwapFeeLP: buy token invalid"
        );
        uint256 LionPrice = getLionPrice();
        uint256 LPPrice = vault.getMaxPrice(address(LPToken));
        uint256 needLion = LPAmount.mul(LPPrice).div(LionPrice);
        require(needLion <= maxLion, "LionSwapFeeLP: slippage");
        require(
            buyToken.balanceOf(msg.sender) >= needLion,
            "LionSwapFeeLP: Lion balance invalid"
        );
        require(
            buyToken.allowance(msg.sender, address(this)) >= needLion,
            "LionSwapFeeLP: Lion allowance invalid"
        );
        buyToken.safeTransferFrom(msg.sender, address(this), needLion);
        uint256 feeLPAmount = getDiscount(LPAmount);
        feeLP.mintTo(msg.sender, feeLPAmount);

        splitLionOrEsLion(msg.sender, buyToken, needLion);

        emit Swap(msg.sender, buyToken, LPAmount, needLion, feeLPAmount);
    }

    function getLionAmount(uint256 LPAmount) public view returns (uint256) {
        uint256 LionPrice = getLionPrice();
        uint256 LPPrice = vault.getMaxPrice(address(LPToken));
        return LPAmount.mul(LPPrice).div(LionPrice);
    }

    function splitLionOrEsLion(
        address user,
        IERC20 token,
        uint256 amount
    ) private {
        (address parent, ) = IReferral(referral).getUserParentInfo(user);
        (uint256 rate, ) = IReferral(referral).getTradeFeeRewardRate(user);
        uint256 userRewardAmount = amount.mul(rate).div(BasePoint);
        uint256 parentRewardAmount = userRewardAmount;

        uint256 toTeamAmount = amount.mul(toTeamRatio).div(BasePoint);
        uint256 left = amount.sub(toTeamAmount);
        toTeamAmount = toTeamAmount.sub(userRewardAmount).sub(
            parentRewardAmount
        );

        IReferral(referral).updateESLionClaimReward(
            user,
            parent,
            userRewardAmount,
            parentRewardAmount
        );


        if (token == LionToken) {
            //lion Token will vest to eslion Token
            token.safeTransfer(
                vestAddress,
                amount
            );
            if(userRewardAmount.add(parentRewardAmount) > 0){
                esLionToken.safeTransfer(
                    address(referral),
                    userRewardAmount.add(parentRewardAmount)
                );
            }
            esLionToken.safeTransfer(earnAddress, left);
            esLionToken.safeTransfer(teamAddress, toTeamAmount);
        } else {
            if(userRewardAmount.add(parentRewardAmount) > 0){
                token.safeTransfer(
                    address(referral),
                    userRewardAmount.add(parentRewardAmount)
                );
            }
            token.safeTransfer(earnAddress, left);
            token.safeTransfer(teamAddress, toTeamAmount);
        }
    }

    function getDiscount(uint256 LPAmount) public view returns (uint256) {
        //10000 LPAmount*10000/1000 discount 90%
        //5000  LPAmount*10000/2000 discount 80%
        //2000  LPAmount*10000/3000 discount 70%
        return LPAmount.mul(BasePoint).div(discountLevel[LPAmount]);
    }


    function getLionPrice() public view returns (uint256) {
        uint32 twapInterval = 3600;
        address[] memory paths = new address[](3);
        uint24[] memory fees = pairFees;//[3000, 500]
        paths[0] = address(LionToken);
        paths[1] = address(weth);
        paths[2] = address(usdc);

        return uinswapOracleV3.getSqrtTWAP(paths,fees, twapInterval);
    }

    function setToken(
        IERC20 _usdc,
        IERC20 _LionToken,
        IERC20 _LPToken,
        IFeeLP _feeLP
    ) external onlyOwner {
        usdc = _usdc;
        LionToken = _LionToken;
        LPToken = _LPToken;
        feeLP = _feeLP;
    }

    function setDiscount(
        uint256 _BasePoint,
        uint256[] memory _discountLevelKey,
        uint256[] memory _discountLevelValue
    ) external onlyOwner {
        require(
            _discountLevelKey.length == _discountLevelValue.length,
            "LionSwapFeeLP: params invalid"
        );
        BasePoint = _BasePoint;
        for (uint i; i < _discountLevelKey.length; i++) {
            discountLevel[_discountLevelKey[i]] = _discountLevelValue[i];
        }
    }

    function setVault(IVault _vault) external onlyOwner {
        vault = _vault;
    }

    function setPairFees(uint24[] calldata _pairFees) external onlyOwner {
        pairFees = _pairFees;
    }

    function setReferral(address _referral) external onlyOwner {
        referral = IReferral(_referral);
    }
    function setFeeParams(
        address _teamAddress,
        address _vestAddress,
        address _earnAddress,
        uint256 _toTeamRatio,
        uint256 _BasePoint
    ) external onlyOwner {
        teamAddress = _teamAddress;
        vestAddress = _vestAddress;
        earnAddress = _earnAddress;
        toTeamRatio = _toTeamRatio;
        BasePoint = _BasePoint;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

