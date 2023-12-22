// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./ERC20.sol";
import "./ChamSlizSolidStaker.sol";
import "./IWrappedBribeFactory.sol";
import "./IFeeConfig.sol";

contract SolidLizardStaker is ChamSlizSolidStaker {
    using SafeERC20 for IERC20;

    // Needed addresses
    address[] public activeVoteLps;
    address public coFeeRecipient;
    IFeeConfig public coFeeConfig;

    ISolidlyRouter.Routes[] public slizToNativeRoute;

    // Events
    event SetChamSLIZRewardPool(address oldPool, address newPool);
    event SetRouter(address oldRouter, address newRouter);
    event SetBribeFactory(address oldFactory, address newFactory);
    event SetFeeRecipient(address oldRecipient, address newRecipient);
    event SetFeeId(uint256 id);
    event RewardsHarvested(uint256 amount);
    event Voted(address[] votes, int256[] weights);
    event ChargedFees(uint256 callFees, uint256 coFees, uint256 strategistFees);
    event MergeVe(address indexed user, uint256 veTokenId, uint256 amount);
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _reserveRate,
        address _proxy,
        address[] memory _manager,
        address _coFeeRecipient,
        address _coFeeConfig,
        ISolidlyRouter.Routes[] memory _slizToNativeRoute
    )
        ChamSlizSolidStaker(
            _name,
            _symbol,
            _reserveRate,
            _proxy,
            _manager[0],
            _manager[1],
            _manager[2],
            _manager[3],
            _manager[4]
        )
    {
        coFeeRecipient = _coFeeRecipient;
        coFeeConfig = IFeeConfig(_coFeeConfig);

        for (uint i; i < _slizToNativeRoute.length; i++) {
            slizToNativeRoute.push(_slizToNativeRoute[i]);
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
        uint256 _tokenId = proxy.tokenId();
        for (uint i; i < len; i++) {
            lpsVoted[i] = solidVoter.poolVote(_tokenId, i);
            votes[i] = solidVoter.votes(_tokenId, lpsVoted[i]);
        }
        lastVoted = solidVoter.lastVote(_tokenId);
    }

    // Claim veToken emissions and increases locked amount in veToken
    function claimVeEmissions() public override {
        uint256 _amount = proxy.claimVeEmissions();
        uint256 gap = totalWant() - totalSupply();
        if (gap > 0) {
            _mint(daoWallet, gap);
        }
        emit ClaimVeEmissions(msg.sender, _amount);
    }

    // vote for emission weights
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
        // We claim first to maximize our voting power.
        claimVeEmissions();
        proxy.vote(_tokenVote, _weights);
        emit Voted(_tokenVote, _weights);
    }

    // claim owner rewards such as trading fees and bribes from gauges swap to thena, notify reward pool
    function harvest() public {
        uint256 before = balanceOfWant();
        uint256 chamSLIZbefore = balanceOf(address(this));
        for (uint i; i < activeVoteLps.length; i++) {
            proxy.getBribeReward(activeVoteLps[i]);
            proxy.getTradingFeeReward(activeVoteLps[i]);
        }
        uint256 rewardBal = balanceOfWant() - before;
        uint256 rewardChamSLIZBal = balanceOf(address(this)) - chamSLIZbefore;
        _chargeSLIZFees(rewardBal);
        _chargeChamSLIZFees(rewardChamSLIZBal);
    }

    function _chargeSLIZFees(uint256 _rewardBal) internal {
        IFeeConfig.FeeCategory memory fees = coFeeConfig.getFees(address(this));
        uint256 feeBal = (_rewardBal * fees.total) / 1e18;
        if (feeBal > 0) {
            IERC20(want).safeApprove(address(router), feeBal);
            router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                feeBal,
                0,
                slizToNativeRoute,
                address(coFeeRecipient),
                block.timestamp
            );
            IERC20(want).safeApprove(address(router), 0);
            emit ChargedFees(0, feeBal, 0);
        }

        IERC20(want).safeTransfer(daoWallet, _rewardBal - feeBal);
        emit RewardsHarvested(_rewardBal);
    }

    function _chargeChamSLIZFees(uint256 _rewardBal) internal {
        IFeeConfig.FeeCategory memory fees = coFeeConfig.getFees(address(this));
        uint256 feeBal = (_rewardBal * fees.total) / 1e18;
        if (feeBal > 0) {
            transfer(address(coFeeRecipient), feeBal);
            emit ChargedFees(0, feeBal, 0);
        }

        transfer(daoWallet, _rewardBal - feeBal);
        emit RewardsHarvested(_rewardBal);
    }

    // Set fee id on fee config
    function setFeeId(uint256 id) external onlyManager {
        emit SetFeeId(id);
        coFeeConfig.setStratFeeId(id);
    }

    // Set fee recipient
    function setCoFeeRecipient(address _feeRecipient) external onlyOwner {
        emit SetFeeRecipient(address(coFeeRecipient), _feeRecipient);
        coFeeRecipient = _feeRecipient;
    }

    // Set our router to exchange our rewards, also update new thenaToNative route.
    function setRouterAndRoute(
        address _router,
        ISolidlyRouter.Routes[] calldata _route
    ) external onlyOwner {
        emit SetRouter(address(router), _router);
        for (uint i; i < slizToNativeRoute.length; i++) slizToNativeRoute.pop();
        for (uint i; i < _route.length; i++) slizToNativeRoute.push(_route[i]);

        router = ISolidlyRouter(_router);
    }

    function mergeVe(uint256 _tokenId) external {
        ve.transferFrom(address(this), address(proxy), _tokenId);
        proxy.merge(_tokenId);
        uint256 gap = totalWant() - totalSupply();
        if (gap > 0) {
            _mint(daoWallet, gap);
        }
        emit MergeVe(msg.sender, _tokenId, gap);
    }
}
