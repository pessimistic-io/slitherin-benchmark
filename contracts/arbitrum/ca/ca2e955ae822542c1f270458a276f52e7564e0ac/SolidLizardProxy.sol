// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./Ownable.sol";
import "./SafeERC20.sol";
import "./IVeToken.sol";
import "./IVoter.sol";
import "./IVeDist.sol";
import "./IMinter.sol";
import "./IController.sol";
import "./ISolidlyRouter.sol";
import "./ISolidLizardGauge.sol";
import "./ISolidlyGauge.sol";
import "./IPairFactory.sol";

contract SolidLizardProxy is Ownable {
    using SafeERC20 for IERC20;

    // Voted Gauges
    struct Gauges {
        address bribe;
        address[] bribeTokens;
        address[] feeTokens;
        address[] rewardTokens;
    }

    IERC20 public immutable SLIZ;
    IVeToken public immutable ve;
    IVeDist public immutable veDist;
    IVoter public immutable solidVoter;
    ISolidlyRouter public router;

    address public lpDepositor;
    address public chamSLIZ;

    address public pendingLpDepositor;
    address public pendingChamSLIZ;
    uint256 public newAddressDeadline;

    uint256 public constant MAX_LOCK = 365 days * 4;
    uint256 public tokenId;

    mapping(address => bool) isApproved;

    mapping(address => Gauges) public gauges;
    mapping(address => bool) public lpInitialized;
    mapping(address => ISolidlyRouter.Routes[]) public routes;

    event SetAddresses(address _chamSLIZ, address lpDepositor);
    event AddedGauge(address bribe, address[] bribeTokens, address[] feeTokens, address[] rewardTokens);
    event AddedRewardToken(address token);
    event NewAddressesCommitted(address chamSLIZ, address lpDepositor, uint256 newAddressDeadline);

    constructor(IERC20 _SLIZ, IVoter _solidVoter, ISolidlyRouter _router) {
        SLIZ = _SLIZ;
        solidVoter = _solidVoter;
        ve = IVeToken(_solidVoter.ve());
        router = _router;

        IMinter _minter = IMinter(_solidVoter.minter());
        IController _controller = IController(_minter.controller());
        veDist = IVeDist(_controller.veDist());

        SLIZ.safeApprove(address(ve), type(uint256).max);
    }

    modifier onlyChamSLIZ() {
        require(msg.sender == chamSLIZ, "Proxy: FORBIDDEN");
        _;
    }

    modifier onlyLPDepositor() {
        require(msg.sender == lpDepositor, "Proxy: FORBIDDEN");
        _;
    }

    function setAddresses(
        address _chamSLIZ,
        address _lpDepositor
    ) external onlyOwner {
        require(address(chamSLIZ) == address(0), "Proxy: ALREADY_SET");
        chamSLIZ = _chamSLIZ;
        lpDepositor = _lpDepositor;

        emit SetAddresses(_chamSLIZ, _lpDepositor);
    }

    function createLock(
        uint256 _amount,
        uint256 _lock_duration
    ) external onlyChamSLIZ returns (uint256 _tokenId) {
        require(tokenId == 0, "ChamSlizStaker: ASSIGNED");
        _tokenId = ve.createLock(_amount, _lock_duration);
        tokenId = _tokenId;
    }

    function merge(uint256 _from) external {
        require(
            ve.ownerOf(_from) == address(this),
            "Proxy: OWNER_IS_NOT_PROXY"
        );
        ve.merge(_from, tokenId);
    }

    function increaseAmount(uint256 _amount) external onlyChamSLIZ {
        ve.increaseAmount(tokenId, _amount);
    }

    function increaseUnlockTime() external onlyChamSLIZ {
        ve.increaseUnlockTime(tokenId, MAX_LOCK);
    }

    function resetVote() external onlyChamSLIZ {
        solidVoter.reset(tokenId);
    }

    function release() external onlyChamSLIZ {
        uint256 before = SLIZ.balanceOf(address(this));
        ve.withdraw(tokenId);
        uint256 amount = SLIZ.balanceOf(address(this)) - before;
        if (amount > 0) SLIZ.safeTransfer(chamSLIZ, amount);
        tokenId = 0;
    }

    function whitelist(address _token) external onlyOwner {
        solidVoter.whitelist(_token, tokenId);
    }

    function locked() external view returns (uint256 amount, uint256 endTime) {
        return ve.locked(tokenId);
    }

    function pause() external onlyChamSLIZ {
        SLIZ.safeApprove(address(ve), 0);
    }

    function unpause() external onlyChamSLIZ {
        SLIZ.safeApprove(address(ve), type(uint256).max);
    }

    function deposit(address _token, uint256 _amount) external onlyLPDepositor {
        address gauge = solidVoter.gauges(_token);
        if (!isApproved[_token]) {
            IERC20(_token).safeApprove(address(gauge), type(uint256).max);
            isApproved[_token] = true;
        }

        ISolidLizardGauge(gauge).deposit(_amount, tokenId);
    }

    function withdraw(
        address _receiver,
        address _token,
        uint256 _amount
    ) external onlyLPDepositor {
        address gauge = solidVoter.gauges(_token);
        ISolidLizardGauge(gauge).withdraw(_amount);
        IERC20(_token).transfer(_receiver, _amount);
    }

    function claimVeEmissions() external onlyChamSLIZ returns (uint256) {
        return veDist.claim(tokenId);
    }

    function totalDeposited(address _token) external view returns (uint) {
        address gauge = solidVoter.gauges(_token);
        return ISolidLizardGauge(gauge).balanceOf(address(this));
    }

    function totalLiquidityOfGauge(
        address _token
    ) external view returns (uint) {
        address gauge = solidVoter.gauges(_token);
        return ISolidLizardGauge(gauge).totalSupply();
    }

    function votingBalance() external view returns (uint) {
        return ve.balanceOfNFT(tokenId);
    }

    function votingTotal() external view returns (uint) {
        return ve.totalSupply();
    }

    // Voting
    function vote(
        address[] calldata _tokenVote,
        int256[] calldata _weights
    ) external onlyChamSLIZ {
        solidVoter.vote(tokenId, _tokenVote, _weights);
    }

    // Add gauge
    function addGauge(
        address _lp,
        address[] calldata _bribeTokens,
        address[] calldata _feeTokens,
        address[] calldata _rewardTokens
    ) external onlyOwner {
        address gauge = solidVoter.gauges(_lp);
        gauges[_lp] = Gauges(
            solidVoter.bribes(gauge),
            _bribeTokens,
            _feeTokens,
            _rewardTokens
        );
        lpInitialized[_lp] = true;
        emit AddedGauge(solidVoter.bribes(gauge), _bribeTokens, _feeTokens, _rewardTokens);
    }

    // Delete a reward token
    function deleteRewardToken(address _token) external onlyOwner {
        delete routes[_token];
    }

    // Add multiple reward tokens
    function addMultipleRewardTokens(
        ISolidlyRouter.Routes[][] calldata _routes
    ) external onlyOwner {
        for (uint256 i; i < _routes.length; i++) {
            addRewardToken(_routes[i]);
        }
    }

    // Add a reward token
    function addRewardToken(
        ISolidlyRouter.Routes[] calldata _route
    ) public onlyOwner {
        address _rewardToken = _route[0].from;
        require(_rewardToken != address(SLIZ), "Proxy: ROUTE_FROM_IS_SLIZ");
        require(
            _route[_route.length - 1].to == address(SLIZ),
            "Proxy: ROUTE_TO_NOT_SLIZ"
        );
        for (uint256 i; i < _route.length; i++) {
            routes[_rewardToken].push(_route[i]);
        }
        IERC20(_rewardToken).approve(address(router), type(uint256).max);
        emit AddedRewardToken(_rewardToken);
    }

    function getBribeReward(address _lp) external onlyChamSLIZ {
        Gauges memory _gauges = gauges[_lp];
        ISolidlyGauge(_gauges.bribe).getReward(tokenId, _gauges.bribeTokens);

        for (uint256 i; i < _gauges.bribeTokens.length; ++i) {
            address bribeToken = _gauges.bribeTokens[i];
            uint256 tokenBal = IERC20(bribeToken).balanceOf(address(this));
            if (tokenBal > 0) {
                if (bribeToken == address(SLIZ) || bribeToken == address(chamSLIZ)) {
                    IERC20(bribeToken).safeTransfer(chamSLIZ, tokenBal);
                } else {
                    router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                        tokenBal,
                        0,
                        routes[bribeToken],
                        chamSLIZ,
                        block.timestamp
                    );
                }
            }
        }
    }

    function getTradingFeeReward(address _lp) external onlyChamSLIZ {
        Gauges memory _gauges = gauges[_lp];
        IPairFactory(_lp).claimFees();
        for (uint256 i; i < _gauges.feeTokens.length; ++i) {
            address feeToken = _gauges.feeTokens[i];
            uint256 tokenBal = IERC20(feeToken).balanceOf(address(this));
            if (tokenBal > 0) {
                if (feeToken == address(SLIZ) || feeToken == address(chamSLIZ)) {
                    IERC20(feeToken).safeTransfer(chamSLIZ, tokenBal);
                } else {
                    router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                        tokenBal,
                        0,
                        routes[feeToken],
                        chamSLIZ,
                        block.timestamp
                    );
                }
            }
        }
    }

    function claimableReward(address _lp) external view returns (uint256) {
        address gauge = solidVoter.gauges(_lp);
        Gauges memory _gauges = gauges[_lp];

        uint256 totalReward = 0;
        for (uint256 i; i < _gauges.rewardTokens.length; ++i) {
            address rewardToken = _gauges.rewardTokens[i];
            
            uint256 reward = ISolidLizardGauge(gauge).earned(rewardToken, address(this));
            if (reward > 0) {
                if (rewardToken != address(SLIZ)) {
                    uint256 rewardSLIZ = router.getAmountsOut(reward, routes[rewardToken])[routes[rewardToken].length];
                    totalReward = totalReward + rewardSLIZ;
                } else {
                    totalReward = totalReward + reward;
                }
            }
        }

        return totalReward;
    }

    function getReward(address _lp) external onlyLPDepositor {
        Gauges memory _gauges = gauges[_lp];
        address gauge = solidVoter.gauges(_lp);
        ISolidLizardGauge(gauge).getReward(address(this), _gauges.rewardTokens);

        for (uint256 i; i < _gauges.rewardTokens.length; ++i) {
            address rewardToken = _gauges.rewardTokens[i];
            uint256 tokenBal = IERC20(rewardToken).balanceOf(address(this));
            if (tokenBal > 0) {
                if (rewardToken != address(SLIZ)) {
                    router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                        tokenBal,
                        0,
                        routes[rewardToken],
                        lpDepositor,
                        block.timestamp
                    );
                } else SLIZ.safeTransfer(lpDepositor, tokenBal);
            }
        }
    }

    /**
        @notice Modify core protocol addresses
        @dev This will brick the existing deployment, it is only intended to be used in case
        of an emergency requiring a complete migration of the protocol. As an additional
        safety mechanism, there is a 7 day delay required between setting and applying
        the new addresses.
    */
    function setPendingAddresses(
        address _chamSLIZ,
        address _lpDepositor
    ) external onlyOwner {
        pendingLpDepositor = _lpDepositor;
        pendingChamSLIZ = _chamSLIZ;
        newAddressDeadline = block.timestamp + 86400 * 7;

        emit NewAddressesCommitted(_chamSLIZ, _lpDepositor, newAddressDeadline);
    }

    function applyPendingAddresses() external onlyOwner {
        require(newAddressDeadline != 0 && newAddressDeadline < block.timestamp, "Proxy: PENDING_TIME");
        chamSLIZ = pendingChamSLIZ;
        lpDepositor = pendingLpDepositor;

        emit SetAddresses(chamSLIZ, lpDepositor);
        rejectPendingAddresses();
    }

    function rejectPendingAddresses() public onlyOwner {
        pendingChamSLIZ = address(0);
        pendingLpDepositor = address(0);
        newAddressDeadline = 0;

        emit NewAddressesCommitted(address(0), address(0), 0);
    }
}

