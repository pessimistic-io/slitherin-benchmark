// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./OwnableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IVeToken.sol";
import "./IVoter.sol";
import "./IVeDist.sol";
import "./IMinter.sol";
import "./ISolidlyRouter.sol";
import "./ISolidlyGauge.sol";

contract CpCHRProxy is OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // Voted Gauges
    struct Gauges {
        address bribeGauge;
        address feeGauge;
        address[] bribeTokens;
        address[] feeTokens;
    }

    IERC20Upgradeable public CHR;
    IVeToken public ve;
    IVeDist public veDist;
    IVoter public solidVoter;
    ISolidlyRouter public router;

    address public cpCHR;

    // Vote weight decays linearly over time. Lock time cannot be more than `MAX_LOCK` (2 years).
    uint256 public constant MAX_LOCK = 365 days * 2;
    uint256 public constant MAX_RATE = 1e18;

    uint256 public mainTokenId;
    uint256 public reserveTokenId;
    uint256 public redeemTokenId;

    mapping(address => Gauges) public gauges;
    mapping(address => bool) public lpInitialized;
    mapping(address => ISolidlyRouter.Routes[]) public routes;

    address public extension;

    event SetCpCHR(address oldValue, address newValue);
    event AddedGauge(address gauge, address feeGauge, address[] bribeTokens, address[] feeTokens);
    event AddedRewardToken(address token);
    event SetRedeemTokenId(uint256 oldValue, uint256 newValue);

    event SetSolidVoter(address oldValue, address newValue);
    event SetVeDist(address oldValue, address newValue);

    function initialize(IVoter _solidVoter, ISolidlyRouter _router) public initializer {
        __Ownable_init();

        solidVoter = IVoter(_solidVoter);
        ve = IVeToken(solidVoter._ve());
        CHR = IERC20Upgradeable(ve.token());
        // IMinter _minter = IMinter(solidVoter.minter());
        // veDist = IVeDist(_minter._rewards_distributor());
        
        router = _router;
        CHR.safeApprove(address(ve), type(uint256).max);
    }

    modifier onlyCpCHR() {
        require(msg.sender == cpCHR, "Proxy: FORBIDDEN");
        _;
    }

    modifier onlyExtension() {
        require(msg.sender == extension, "Proxy: EXTENSION_FORBIDDEN");
        _;
    }

    function setCpCHR(address _cpCHR) external onlyOwner {
        require(address(cpCHR) == address(0), "Proxy: ALREADY_SET");
        emit SetCpCHR(cpCHR, _cpCHR);
        cpCHR = _cpCHR;
    }

    function createMainLock(uint256 _amount, uint256 _lock_duration) external onlyCpCHR {
        require(mainTokenId == 0, "Proxy: ASSIGNED");
        mainTokenId = ve.create_lock(_amount, _lock_duration);
    }

    function createReserveLock(uint256 _amount, uint256 _lock_duration) external onlyCpCHR {
        require(reserveTokenId == 0, "Proxy: ASSIGNED");
        reserveTokenId = ve.create_lock(_amount, _lock_duration);
        redeemTokenId = reserveTokenId;
    }

    function merge(uint256 _from, uint256 _to) external {
        require(_to == mainTokenId || _to == reserveTokenId, "Proxy: TO_TOKEN_INVALID");
        require(_from != mainTokenId && _from != reserveTokenId, "Proxy: NOT_MERGE_BUSINESS_TOKEN");
        require(ve.ownerOf(_from) == address(this), "Proxy: OWNER_IS_NOT_PROXY");
        ve.merge(_from, _to);
    }

    function increaseAmount(uint256 _tokenId, uint256 _amount) external onlyCpCHR {
        ve.increase_amount(_tokenId, _amount);
    }

    function increaseUnlockTime() external onlyCpCHR {
        uint256 unlockTime = (block.timestamp + MAX_LOCK) / 1 weeks * 1 weeks;
        (, uint256 mainEndTime) = ve.locked(mainTokenId);
        (, uint256 reserveEndTime) = ve.locked(reserveTokenId);
        if (unlockTime > mainEndTime) ve.increase_unlock_time(mainTokenId, MAX_LOCK);
        if (unlockTime > reserveEndTime) ve.increase_unlock_time(reserveTokenId, MAX_LOCK);
    }

    function _split(uint256[] memory _amounts, uint256 _tokenId) internal returns (uint256 tokenId0, uint256 tokenId1) {
        uint256 totalNftBefore = ve.balanceOf(address(this));
        ve.split(_amounts, _tokenId);
        uint256 totalNftAfter = ve.balanceOf(address(this));
        require(totalNftAfter == totalNftBefore + 1, "Proxy: SPLIT_NFT_FAILED");
        
        tokenId1 = ve.tokenOfOwnerByIndex(address(this), totalNftAfter - 1);
        tokenId0 = ve.tokenOfOwnerByIndex(address(this), totalNftAfter - 2);
    }

    function splitWithdraw(uint256 _amount) external onlyCpCHR returns (uint256) {
        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = _amount;
        _amounts[1] = withdrawableBalance() - _amount;
        (uint256 tokenIdForUser, uint256 tokenIdRemaining) = _split(_amounts, redeemTokenId);
        if (mainTokenId == redeemTokenId) {
            mainTokenId = tokenIdRemaining;
        } else {
            reserveTokenId = tokenIdRemaining;
        }

        redeemTokenId = tokenIdRemaining;
        ve.transferFrom(address(this), msg.sender, tokenIdForUser);
        return tokenIdForUser;
    }

    function split(uint256 _amount) external onlyOwner {
        require(mainTokenId > 0 && reserveTokenId > 0, "CpCHR: NOT_ASSIGNED");
        uint256 totalMainAmount = balanceOfWantInMainVe();
        uint256 reserveAmount = balanceOfWantInReserveVe();
        require(_amount < totalMainAmount - MAX_RATE, "CpCHR: INSUFFICIENCY_AMOUNT_OUT");
        if (_amount > 0) {
            uint256[] memory _amounts = new uint256[](2);
            _amounts[0] = _amount;
            _amounts[1] = totalMainAmount - _amount;
            (uint256 tokenIdToMergeReserve, uint256 newMainTokenId) = _split(_amounts, mainTokenId);
            if (redeemTokenId == mainTokenId) {
                redeemTokenId = newMainTokenId;
            }

            mainTokenId = newMainTokenId;
            ve.merge(tokenIdToMergeReserve, reserveTokenId);
            require(balanceOfWantInReserveVe() == reserveAmount + _amount, "CpCHR: SPLIT_ERROR");
        }
    }

    function setRedeemTokenId(uint256 _tokenId) external onlyOwner {
        require(_tokenId == mainTokenId || _tokenId == reserveTokenId, "Proxy: NOT_ASSIGNED_TOKEN");
        emit SetRedeemTokenId(redeemTokenId, _tokenId);
        redeemTokenId = _tokenId;
    }

    function withdrawableBalance() public view returns (uint256 wants) {
        (wants, ) = ve.locked(redeemTokenId);
    }

    function balanceOfWantInMainVe() public view returns (uint256 wants) {
        (wants, ) = ve.locked(mainTokenId);
    }

    function balanceOfWantInReserveVe() public view returns (uint256 wants) {
        (wants, ) = ve.locked(reserveTokenId);
    }

    function resetVote(uint256 _tokenId) external onlyCpCHR {
        solidVoter.reset(_tokenId);
    }

    function approveVe(address _approved, uint _tokenId) external onlyOwner {
        ve.approve(_approved, _tokenId);
    }

    function release(uint256 _tokenId) external onlyCpCHR {
        uint256 before = CHR.balanceOf(address(this));
        ve.withdraw(mainTokenId);
        uint256 amount = CHR.balanceOf(address(this)) - before;
        if (amount > 0) CHR.safeTransfer(cpCHR, amount);
        if (_tokenId == mainTokenId) mainTokenId = 0;
        if (_tokenId == reserveTokenId) reserveTokenId = 0;
    }

    function whitelist(uint256 _tokenId, address _token) external onlyOwner {
        solidVoter.whitelist(_token, _tokenId);
    }

    function locked(uint256 _tokenId) external view returns (uint256 amount, uint256 endTime) {
        return ve.locked(_tokenId);
    }

    // function claimVeEmissions() external onlyCpCHR returns (uint256) {
    //     uint256 reward = veDist.claim(mainTokenId);
    //     if (reserveTokenId > 0) {
    //         reward = reward + veDist.claim(reserveTokenId);
    //     }
        
    //     return reward;
    // }

    // Voting
    function vote(
        uint256 _tokenId,
        address[] calldata _tokenVote,
        uint256[] calldata _weights
    ) external onlyCpCHR {
        solidVoter.vote(_tokenId, _tokenVote, _weights);
    }

    // Add gauge
    function addGauge(address _lp, address[] calldata _bribeTokens, address[] calldata _feeTokens) external onlyOwner {
        address gauge = solidVoter.gauges(_lp);
        gauges[_lp] = Gauges(solidVoter.external_bribes(gauge), solidVoter.internal_bribes(gauge), _bribeTokens, _feeTokens);
        lpInitialized[_lp] = true;
        emit AddedGauge(solidVoter.external_bribes(gauge), solidVoter.internal_bribes(gauge), _bribeTokens, _feeTokens);
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
        require(_rewardToken != address(CHR), "Proxy: ROUTE_FROM_IS_CHR");
        require(
            _route[_route.length - 1].to == address(CHR),
            "Proxy: ROUTE_TO_NOT_CHR"
        );
        for (uint256 i; i < _route.length; i++) {
            routes[_rewardToken].push(_route[i]);
        }
        IERC20Upgradeable(_rewardToken).approve(address(router), type(uint256).max);
        emit AddedRewardToken(_rewardToken);
    }

    function setSolidVoter(address _solidVoter) external onlyCpCHR {
        emit SetSolidVoter(address(solidVoter), _solidVoter);
        solidVoter = IVoter(_solidVoter);
    }

    // function setVeDist(address _veDist) external onlyCpCHR {
    //     emit SetVeDist(address(veDist), _veDist);
    //     veDist = IVeDist(_veDist);
    // }

    function setExtension(address _extension) external onlyOwner {
        extension = _extension;
    }

    function externalCall(address _target, bytes calldata _calldata) external payable onlyExtension returns (bool _success, bytes memory _result) {
        require(extension != address(0));
        return _target.call{value: msg.value}(_calldata);
    }

    function getBribeReward(uint256 _tokenId, address _lp) external onlyCpCHR {
        Gauges memory _gauges = gauges[_lp];
        ISolidlyGauge(_gauges.bribeGauge).getReward(_tokenId, _gauges.bribeTokens);

        for (uint256 i; i < _gauges.bribeTokens.length; ++i) {
            address bribeToken = _gauges.bribeTokens[i];
            uint256 tokenBal = IERC20Upgradeable(bribeToken).balanceOf(address(this));
            if (tokenBal > 0) {
                if (bribeToken == address(CHR) || bribeToken == address(cpCHR)) {
                    IERC20Upgradeable(bribeToken).safeTransfer(cpCHR, tokenBal);
                } else {
                    router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                        tokenBal,
                        0,
                        routes[bribeToken],
                        address(cpCHR),
                        block.timestamp
                    );
                }
            }
        }
    }

    function getTradingFeeReward(uint256 _tokenId, address _lp) external onlyCpCHR {
        Gauges memory _gauges = gauges[_lp];
        ISolidlyGauge(_gauges.feeGauge).getReward(_tokenId, _gauges.feeTokens);

        for (uint256 i; i < _gauges.feeTokens.length; ++i) {
            address feeToken = _gauges.feeTokens[i];
            uint256 tokenBal = IERC20Upgradeable(feeToken).balanceOf(address(this));
            if (tokenBal > 0) {
                if (feeToken == address(CHR) || feeToken == address(cpCHR)) {
                    IERC20Upgradeable(feeToken).safeTransfer(cpCHR, tokenBal);
                } else {
                    router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                        tokenBal,
                        0,
                        routes[feeToken],
                        address(cpCHR),
                        block.timestamp
                    );
                }
            }
        }
    }
}
