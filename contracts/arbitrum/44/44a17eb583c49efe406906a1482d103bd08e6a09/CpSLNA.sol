// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./CpSLNASolidStaker.sol";

contract CpSLNA is CpSLNASolidStaker {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address[] public activeVoteLps;
    IRouter.Routes[] public wantToNativeRoute;

    // Events
    event ClaimVeEmissions(address indexed user, uint256 amount);
    event SetRouter(address oldRouter, address newRouter);
    event RewardsHarvested(uint256 _rewardSLNABal, uint256 _rewardChamSLNABal);
    event Voted(address[] votes, int256[] weights);
    event ChargedFees(uint256 callFees, uint256 coFees, uint256 strategistFees);
    event MergeVe(address indexed user, uint256 veTokenFromId, uint256 amount);
    
    function initialize(
        string memory _name,
        string memory _symbol,
        address _proxy,
        address[] memory _manager,
        address _configurator,
        IRouter.Routes[] memory _wantToNativeRoute
    ) public initializer {
        CpSLNASolidStaker.init(_name, _symbol, _proxy, _manager[0], _manager[1], _manager[2], _manager[3], _configurator);

        for (uint i; i < _wantToNativeRoute.length; i++) {
            wantToNativeRoute.push(_wantToNativeRoute[i]);
        }
    }

    // Vote information
    function voteInfo()
        external
        view
        returns (
            address[] memory lpsVoted,
            uint256[] memory votes,
            uint256 lastVoted
        )
    {
        uint256 len = activeVoteLps.length;
        lpsVoted = new address[](len);
        votes = new uint256[](len);
        uint256 _tokenId = proxy.mainTokenId();
        for (uint i; i < len; i++) {
            lpsVoted[i] = solidVoter.poolVote(_tokenId, i);
            votes[i] = solidVoter.votes(_tokenId, lpsVoted[i]);
        }
        lastVoted = solidVoter.lastVote(_tokenId);
    }

    // Claim veToken emissions and increases locked amount in veToken
    function claimVeEmissions() public {
        uint256 amount = proxy.claimVeEmissions();
        uint256 gap = totalWant() - totalSupply();
        if (gap > 0) {
            _mint(daoWallet, gap);
        }

        emit ClaimVeEmissions(msg.sender, amount);
    }

    function vote(
        address[] calldata _tokenVote,
        int256[] calldata _weights,
        bool _withHarvest
    ) external onlyVoter {
        // Check to make sure we set up our rewards
        for (uint i; i < _tokenVote.length; i++) {
            require(proxy.lpInitialized(_tokenVote[i]), "Staker: TOKEN_VOTE_INVALID");
        }

        if (_withHarvest) harvest();
        activeVoteLps = _tokenVote;

        uint256 tokenId = proxy.mainTokenId();
        claimVeEmissions();
        proxy.vote(tokenId, _tokenVote, _weights);
        emit Voted(_tokenVote, _weights);
    }

    function harvest() public {
        uint256 before = balanceOfWant();

        _getVotedReward(proxy.mainTokenId(), activeVoteLps);
        
        uint256 rewardBal = balanceOfWant() - before;
        uint256 rewardCpSLNABal = balanceOf(address(this));
        _chargeFees(rewardBal, rewardCpSLNABal);
    }

    function _getVotedReward(uint256 _tokenId, address[] memory tokenVotes) internal {
        if (_tokenId > 0) {
            for (uint i; i < tokenVotes.length; i++) {
                proxy.getBribeReward(_tokenId, tokenVotes[i]);
                proxy.getFeeReward(tokenVotes[i]);
            }
        }
    }

    function _chargeFees(uint256 _rewardSLNABal, uint256 _rewardCpSLNABal) internal {
        uint256 feePercent = configurator.getFee();
        address coFeeRecipient = configurator.coFeeRecipient();
        if (_rewardSLNABal > 0) {
            uint256 feeBal = (_rewardSLNABal * feePercent) / MAX_RATE;
            if (feeBal > 0) {
                IERC20Upgradeable(want).safeApprove(address(router), feeBal);
                router.swapExactTokensForTokens(
                    feeBal,
                    1,
                    wantToNativeRoute,
                    coFeeRecipient,
                    block.timestamp
                );
                IERC20Upgradeable(want).safeApprove(address(router), 0);
                emit ChargedFees(0, feeBal, 0);
            }

            IERC20Upgradeable(want).safeTransfer(daoWallet, _rewardSLNABal - feeBal);
        }

        if (_rewardCpSLNABal > 0) {
            uint256 feeBal = (_rewardCpSLNABal * feePercent) / MAX_RATE;
            if (feeBal > 0) {
                IERC20Upgradeable(address(this)).safeTransfer(coFeeRecipient, feeBal);
                emit ChargedFees(0, feeBal, 0);
            }

            IERC20Upgradeable(address(this)).safeTransfer(daoWallet, _rewardCpSLNABal - feeBal);
        }

        emit RewardsHarvested(_rewardSLNABal, _rewardCpSLNABal);
    }

    function setRouterAndRoute(
        address _router,
        IRouter.Routes[] calldata _route
    ) external onlyOwner {
        emit SetRouter(address(router), _router);
        delete wantToNativeRoute;
        for (uint i; i < _route.length; i++) wantToNativeRoute.push(_route[i]);
        router = IRouter(_router);
    }

    function mergeVe(uint256 _tokenFromId) external {
        ve.transferFrom(address(this), address(proxy), _tokenFromId);
        proxy.merge(_tokenFromId);
        uint256 gap = totalWant() - totalSupply();
        if (gap > 0) {
            _mint(daoWallet, gap);
        }

        emit MergeVe(msg.sender, _tokenFromId, gap);
    }
}
