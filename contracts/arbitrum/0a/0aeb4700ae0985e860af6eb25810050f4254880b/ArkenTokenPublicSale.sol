// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.16;

import "./Ownable.sol";
import "./SafeERC20.sol";

contract ArkenTokenPublicSale is Ownable {
    using SafeERC20 for IERC20;

    uint256 public immutable price;
    IERC20 public immutable usdc;
    IERC20 public immutable arken;
    address public withdrawer;

    uint256[3] public quota;
    uint256[3] public maxCap;
    uint256[2][3] private _releaseRatio;

    bool[3] public buyable;
    bool[2][3] private _claimable;

    uint256[3] public boughtAmount;
    uint256[3] public claimedAmount;
    
    mapping(address => uint256)[3] private _claimableAmountOf;
    mapping(address => uint256)[2][3] private _claimedAmountOf;

    event Buy(address indexed account, uint8 indexed round, uint256 amount);

    event Claim(address indexed account, uint8 indexed round, uint8 indexed stage, uint256 amount);

    modifier onlyWithdrawer() {
        require(
            msg.sender == withdrawer,
            'ArkenTokenPublicSale: caller is not the withdrawer'
        );
        _;
    }

    constructor(
        uint256 price_,
        address usdc_,
        address arken_,
        address withdrawer_,
        uint256[3] memory quota_,
        uint256[3] memory maxCap_,
        uint256[2][3] memory releaseRatio_
    ) {
        price = price_;
        usdc = IERC20(usdc_);
        arken = IERC20(arken_);
        withdrawer = withdrawer_;
        quota = quota_;
        maxCap = maxCap_;
        _releaseRatio = releaseRatio_;
    }

    function releaseRatio(uint8 round, uint8 stage) external view returns (uint256) {
        return _releaseRatio[round][stage];
    }

    function claimable(uint8 round, uint8 stage) external view returns (bool) {
        return _claimable[round][stage];
    }

    function claimableAmountOf(uint8 round, address account) external view returns (uint256) {
        return _claimableAmountOf[round][account];
    }

    function claimedAmountOf(uint8 round, uint8 stage, address account) external view returns (uint256) {
        return _claimedAmountOf[round][stage][account];
    }

    function withdraw() external onlyWithdrawer {
        usdc.safeTransfer(msg.sender, usdc.balanceOf(address(this)));
    }

    function emergencyWithdrawArken() external onlyOwner {
        arken.safeTransfer(msg.sender, arken.balanceOf(address(this)));
    }

    function setReleaseRatio(uint256[2][3] memory releaseRatio_) external onlyOwner {
        _releaseRatio = releaseRatio_;
    }

    function setBuyable(uint8 round, bool _buyable) external onlyOwner {
        buyable[round] = _buyable;
    }

    function setClaimable(uint8 round, uint8 stage, bool claimable_) external onlyOwner {
        _claimable[round][stage] = claimable_;
    }
    
    function setWithdrawer(address _withdrawer) external onlyOwner {
        withdrawer = _withdrawer;
    }

    function bbbbbbbbbbbbbbbbbbbbb(uint256 amount, uint8 round) external {
        require(buyable[round], 'ArkenTokenPublicSale: can not buy');
        require(
            amount % 10 ** 18 == 0,
            'ArkenTokenPublicSale: decimals are not allowed'
        );
        require(
            ((amount + _claimableAmountOf[round][msg.sender]) / 10**18) * price <= maxCap[round],
            'ArkenTokenPublicSale: mapCap exceeded'
        );
        require(
            amount + boughtAmount[round] <= quota[round],
            'ArkenTokenPublicSale: quota exceeded'
        );

        boughtAmount[round] += amount;
        _claimableAmountOf[round][msg.sender] += amount;
        usdc.safeTransferFrom(
            msg.sender,
            address(this),
            (amount / 10**18) * price
        );

        emit Buy(msg.sender, round, amount);
    }
    
    function claim(uint8 round, uint8 stage) external {
        require(_claimable[round][stage], 'ArkenTokenPublicSale: can not claim');
        require(_claimedAmountOf[round][stage][msg.sender] == 0, 'ArkenTokenPublicSale: already claimed');

        uint256 amount = (_claimableAmountOf[round][msg.sender] * _releaseRatio[round][stage]) / 100;
        require(amount > 0, 'ArkenTokenPublicSale: zero amount');

        _claimedAmountOf[round][stage][msg.sender] = amount;
        claimedAmount[round] += amount;
        arken.safeTransfer(msg.sender, amount);

        emit Claim(msg.sender, round, stage, amount);
    }
}

