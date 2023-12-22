//SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import {IRewardRouterV2} from "./IRewardRouterV2.sol";
import {ERC20} from "./ERC20.sol";
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {Ownable} from "./Ownable.sol";

contract GMXStrategy is Ownable {
    using SafeERC20 for IERC20;

    /*///////////////////////////////////////////////////////////////
                                 Constants  
    //////////////////////////////////////////////////////////////*/

    address public constant ES_GMX = 0xf42Ae1D54fd613C9bb14810b0588FaAa09a426cA;
    address public constant glpManager =
        0x321F653eED006AD1C29D174e17d96351BDe22649;

    /*///////////////////////////////////////////////////////////////
                                 Immutables 
    //////////////////////////////////////////////////////////////*/
    address public immutable weth;

    /*///////////////////////////////////////////////////////////////
                                 State Variables 
    //////////////////////////////////////////////////////////////*/

    address public administrator;
    address public yieldDistributor;
    IRewardRouterV2 public rewardRouterV2;
    uint256 public claimable;
    uint256 public compounded;
    bool public adminRemoved = false;

    /*///////////////////////////////////////////////////////////////
                                 Errors
    //////////////////////////////////////////////////////////////*/

    error NotOwner();
    error NotEnoughYield();
    error TooSoon();
    error AdminRemoved();

    /*///////////////////////////////////////////////////////////////
                                 Events 
    //////////////////////////////////////////////////////////////*/

    event YieldTransfered(address indexed _caller, uint256 _amount);
    event EsGMXStaked(address indexed _caller, uint256 _amount);
    event Unstaked(address indexed _caller, uint256 _amount);
    event GlpMinted(
        address indexed _caller,
        address indexed _token,
        uint256 _amount
    );

    constructor(address _rewardRouterV2, address _weth) {
        rewardRouterV2 = IRewardRouterV2(_rewardRouterV2);
        administrator = msg.sender;
        weth = _weth;
    }

    /*///////////////////////////////////////////////////////////////
                                 User Functions  
    //////////////////////////////////////////////////////////////*/

    function stakeGMXRewards() external {
        require(
            ERC20(ES_GMX).balanceOf(address(this)) > 0,
            "O balance of contract"
        );
        uint256 amount = ERC20(ES_GMX).balanceOf(address(this));
        rewardRouterV2.stakeEsGmx(amount);
        emit EsGMXStaked(msg.sender, amount);
    }

    ///@notice transfers yield to the staking contract
    function transferYield() external {
        uint256 amount = IERC20(weth).balanceOf(address(this));
        if (amount <= 0) {
            revert NotEnoughYield();
        }
        IERC20(weth).safeTransfer(yieldDistributor, amount);
        emit YieldTransfered(msg.sender, amount);
    }

    function mintGLP(
        address _token,
        uint256 _minUsdg,
        uint256 _minGlp
    ) external onlyOwnerOrAdmin {
        uint256 _amount = IERC20(_token).balanceOf(address(this));
        ERC20(_token).increaseAllowance(glpManager, _amount);
        rewardRouterV2.mintAndStakeGlp(_token, _amount, _minUsdg, _minGlp);
        emit GlpMinted(msg.sender, _token, _amount);
    }

    function claimRewards() external {
        if (claimable > block.timestamp) {
            revert TooSoon();
        }
        rewardRouterV2.claim();
        claimable = block.timestamp + 1 days;
    }

    function compound() external {
        if (compounded + 1 days > block.timestamp) {
            revert TooSoon();
        }
        rewardRouterV2.compound();
        compounded = block.timestamp;
    }

    /*///////////////////////////////////////////////////////////////
                                 Admin Functions  
    //////////////////////////////////////////////////////////////*/

    function sellGlp(
        address _tokenOut,
        uint256 _glpAmount,
        uint256 _minOut
    ) external onlyOwnerOrAdmin {
        rewardRouterV2.unstakeAndRedeemGlp(
            _tokenOut,
            _glpAmount,
            _minOut,
            address(this)
        );
    }

    function unstake(uint256 _amount) external onlyOwnerOrAdmin {
        rewardRouterV2.unstakeEsGmx(_amount);
        emit Unstaked(msg.sender, _amount);
    }

    function removeAdmin() external onlyOwner {
        administrator = address(0);
        adminRemoved = true;
    }

    function replaceAdmin(address newAdmin) external onlyOwnerOrAdmin {
        if (adminRemoved != false) {
            revert AdminRemoved();
        }
        administrator = newAdmin;
    }

    function setYieldDistributor(address _yield) external onlyOwnerOrAdmin {
        yieldDistributor = _yield;
    }

    /*///////////////////////////////////////////////////////////////
                            Modifer Functions  
    //////////////////////////////////////////////////////////////*/

    modifier onlyOwnerOrAdmin() {
        if (msg.sender == administrator || msg.sender == owner()) {
            revert NotOwner();
        }
        _;
    }
}

