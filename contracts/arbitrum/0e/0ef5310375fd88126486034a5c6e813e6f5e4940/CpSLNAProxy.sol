// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./OwnableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IVeToken2.sol";
import "./IVoter2.sol";
import "./IVeDist.sol";
import "./IMinter.sol";
import "./IController.sol";
import "./IRouter.sol";
import "./ISolidlyGauge.sol";
import "./IGauge.sol";
import "./IPairFactory.sol";

contract CpSLNAProxy is OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // Voted Gauges
    struct Gauges {
        address bribe;
        address[] bribeTokens;
        address[] feeTokens;
        address[] rewardTokens;
    }

    IERC20Upgradeable public SLNA;
    IVeToken2 public ve;
    IVeDist public veDist;
    IVoter2 public solidVoter;
    IRouter public router;

    address public lpDepositor;
    address public cpSLNA;

    address public pendingLpDepositor;
    address public pendingCpSLNA;
    uint256 public newAddressDeadline;

    uint256 public constant MAX_LOCK = 4 * 365 days;
    uint256 public mainTokenId;

    mapping(address => bool) isApproved;

    mapping(address => Gauges) public gauges;
    mapping(address => bool) public lpInitialized;
    mapping(address => IRouter.Routes[]) public routes;

    event SetCpSLNA(address oldValue, address newValue);
    event SetLPDepositor(address oldValue, address newValue);
    event SetAddresses(address _cpSLNA, address lpDepositor);
    event AddedGauge(address bribe, address[] bribeTokens, address[] feeTokens, address[] rewardTokens);
    event AddedRewardToken(address token);
    event NewAddressesCommitted(address cpSLNA, address lpDepositor, uint256 newAddressDeadline);
    event SetSolidVoter(address oldValue, address newValue);
    event SetVeDist(address oldValue, address newValue);

    function initialize(IVoter2 _solidVoter, IRouter _router) public initializer {
        __Ownable_init();
        solidVoter = _solidVoter;
        ve = IVeToken2(solidVoter.ve());
        SLNA = IERC20Upgradeable(ve.token());
        router = _router;

        IMinter _minter = IMinter(_solidVoter.minter());
        IController _controller = IController(_minter.controller());
        veDist = IVeDist(_controller.veDist());

        SLNA.safeApprove(address(ve), type(uint256).max);
    }

    modifier onlyCpSLNA() {
        require(msg.sender == cpSLNA, "Proxy: FORBIDDEN");
        _;
    }

    modifier onlyLPDepositor() {
        require(msg.sender == lpDepositor, "Proxy: FORBIDDEN");
        _;
    }

    function setCpSLNA(address _cpSLNA) external onlyOwner {
        require(address(cpSLNA) == address(0), "Proxy: ALREADY_SET");
        emit SetCpSLNA(cpSLNA, _cpSLNA);
        cpSLNA = _cpSLNA;
    }

    function setLpDepositor(address _lpDepositor) external onlyOwner {
        require(address(lpDepositor) == address(0), "Proxy: ALREADY_SET");
        emit SetLPDepositor(lpDepositor, _lpDepositor);
        lpDepositor = _lpDepositor;
    }

    function createMainLock(uint256 _amount, uint256 _lock_duration) external onlyCpSLNA returns (uint256) {
        require(mainTokenId == 0, "CpSLNASolidStaker: ASSIGNED");
        mainTokenId = ve.createLock(_amount, _lock_duration);
        return mainTokenId;
    }

    function merge(uint256 _from) external {
        require(_from != mainTokenId, "Proxy: NOT_MERGE_BUSINESS_TOKEN");
        require(ve.ownerOf(_from) == address(this), "Proxy: OWNER_IS_NOT_PROXY");
        ve.merge(_from, mainTokenId);
    }

    function increaseAmount(uint256 _amount) external onlyCpSLNA {
        ve.increaseAmount(mainTokenId, _amount);
    }

    function increaseUnlockTime() external onlyCpSLNA {
        ve.increaseUnlockTime(mainTokenId, MAX_LOCK);
    }

    function resetVote(uint256 _tokenId) external onlyCpSLNA {
        solidVoter.reset(_tokenId);
    }

    function release() external onlyCpSLNA {
        uint256 before = SLNA.balanceOf(address(this));
        ve.withdraw(mainTokenId);
        uint256 amount = SLNA.balanceOf(address(this)) - before;
        if (amount > 0) SLNA.safeTransfer(cpSLNA, amount);
        mainTokenId = 0;
    }

    function whitelist(address _token) external onlyOwner {
        solidVoter.whitelist(_token, mainTokenId);
    }

    function locked(uint256 _tokenId) external view returns (uint256 amount, uint256 endTime) {
        return ve.locked(_tokenId);
    }

    function pause() external onlyCpSLNA {
        SLNA.safeApprove(address(ve), 0);
    }

    function unpause() external onlyCpSLNA {
        SLNA.safeApprove(address(ve), type(uint256).max);
    }

    function deposit(address _token, uint256 _amount) external onlyLPDepositor {
        address gauge = solidVoter.gauges(_token);
        if (!isApproved[_token]) {
            IERC20Upgradeable(_token).safeApprove(address(gauge), type(uint256).max);
            isApproved[_token] = true;
        }

        IGauge(gauge).deposit(_amount, mainTokenId);
    }

    function withdraw(
        address _receiver,
        address _token,
        uint256 _amount
    ) external onlyLPDepositor {
        address gauge = solidVoter.gauges(_token);
        IGauge(gauge).withdraw(_amount);
        IERC20Upgradeable(_token).transfer(_receiver, _amount);
    }

    function claimVeEmissions() external onlyCpSLNA returns (uint256) {
        uint256 reward = veDist.claim(mainTokenId);
        return reward;
    }

    function totalDeposited(address _token) external view returns (uint) {
        address gauge = solidVoter.gauges(_token);
        return IGauge(gauge).balanceOf(address(this));
    }

    function totalLiquidityOfGauge(
        address _token
    ) external view returns (uint) {
        address gauge = solidVoter.gauges(_token);
        return IGauge(gauge).totalSupply();
    }

    function votingBalance() external view returns (uint) {
        return ve.balanceOfNFT(mainTokenId);
    }

    function votingTotal() external view returns (uint) {
        return ve.totalSupply();
    }

    // Voting
    function vote(
        uint256 _tokenId,
        address[] calldata _tokenVote,
        int256[] calldata _weights
    ) external onlyCpSLNA {
        solidVoter.vote(_tokenId, _tokenVote, _weights);
    }

    function approveVe(address _approved, uint _tokenId) external onlyOwner {
        ve.approve(_approved, _tokenId);
    }
    
    function setSolidVoter(address _solidVoter) external onlyCpSLNA {
        emit SetSolidVoter(address(solidVoter), _solidVoter);
        solidVoter = IVoter2(_solidVoter);
    }

    function setVeDist(address _veDist) external onlyCpSLNA {
        emit SetVeDist(address(veDist), _veDist);
        veDist = IVeDist(_veDist);
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
        IRouter.Routes[][] calldata _routes
    ) external onlyOwner {
        for (uint256 i; i < _routes.length; i++) {
            addRewardToken(_routes[i]);
        }
    }

    // Add a reward token
    function addRewardToken(
        IRouter.Routes[] calldata _route
    ) public onlyOwner {
        address _rewardToken = _route[0].from;
        require(_rewardToken != address(SLNA), "Proxy: ROUTE_FROM_IS_SLNA");
        require(
            _route[_route.length - 1].to == address(SLNA),
            "Proxy: ROUTE_TO_NOT_SLNA"
        );
        for (uint256 i; i < _route.length; i++) {
            routes[_rewardToken].push(_route[i]);
        }
        IERC20Upgradeable(_rewardToken).approve(address(router), type(uint256).max);
        emit AddedRewardToken(_rewardToken);
    }

    function getBribeReward(uint256 _tokenId, address _lp) external onlyCpSLNA {
        Gauges memory _gauges = gauges[_lp];
        ISolidlyGauge(_gauges.bribe).getReward(_tokenId, _gauges.bribeTokens);

        for (uint256 i; i < _gauges.bribeTokens.length; ++i) {
            address bribeToken = _gauges.bribeTokens[i];
            uint256 tokenBal = IERC20Upgradeable(bribeToken).balanceOf(address(this));
            if (tokenBal > 0) {
                if (bribeToken == address(SLNA) || bribeToken == address(cpSLNA)) {
                    IERC20Upgradeable(bribeToken).safeTransfer(cpSLNA, tokenBal);
                } else {
                    router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                        tokenBal,
                        0,
                        routes[bribeToken],
                        cpSLNA,
                        block.timestamp
                    );
                }
            }
        }
    }

    function getFeeReward(address _lp) external onlyCpSLNA {
        Gauges memory _gauges = gauges[_lp];
        IPairFactory(_lp).claimFees();
        for (uint256 i; i < _gauges.feeTokens.length; ++i) {
            address feeToken = _gauges.feeTokens[i];
            uint256 tokenBal = IERC20Upgradeable(feeToken).balanceOf(address(this));
            if (tokenBal > 0) {
                if (feeToken == address(SLNA) || feeToken == address(cpSLNA)) {
                    IERC20Upgradeable(feeToken).safeTransfer(cpSLNA, tokenBal);
                } else {
                    router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                        tokenBal,
                        0,
                        routes[feeToken],
                        cpSLNA,
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
            
            uint256 reward = IGauge(gauge).earned(rewardToken, address(this));
            if (reward > 0) {
                if (rewardToken != address(SLNA)) {
                    uint256 rewardSLNA = router.getAmountsOut(reward, routes[rewardToken])[routes[rewardToken].length];
                    totalReward = totalReward + rewardSLNA;
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
        IGauge(gauge).getReward(address(this), _gauges.rewardTokens);

        for (uint256 i; i < _gauges.rewardTokens.length; ++i) {
            address rewardToken = _gauges.rewardTokens[i];
            uint256 tokenBal = IERC20Upgradeable(rewardToken).balanceOf(address(this));
            if (tokenBal > 0) {
                if (rewardToken != address(SLNA)) {
                    router.swapExactTokensForTokens(
                        tokenBal,
                        0,
                        routes[rewardToken],
                        lpDepositor,
                        block.timestamp
                    );
                } else SLNA.safeTransfer(lpDepositor, tokenBal);
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
        address _cpSLNA,
        address _lpDepositor
    ) external onlyOwner {
        pendingLpDepositor = _lpDepositor;
        pendingCpSLNA = _cpSLNA;
        newAddressDeadline = block.timestamp + 86400 * 7;

        emit NewAddressesCommitted(_cpSLNA, _lpDepositor, newAddressDeadline);
    }

    function applyPendingAddresses() external onlyOwner {
        require(newAddressDeadline != 0 && newAddressDeadline < block.timestamp, "Proxy: PENDING_TIME");
        cpSLNA = pendingCpSLNA;
        lpDepositor = pendingLpDepositor;

        emit SetAddresses(cpSLNA, lpDepositor);
        rejectPendingAddresses();
    }

    function rejectPendingAddresses() public onlyOwner {
        pendingCpSLNA = address(0);
        pendingLpDepositor = address(0);
        newAddressDeadline = 0;

        emit NewAddressesCommitted(address(0), address(0), 0);
    }
}
