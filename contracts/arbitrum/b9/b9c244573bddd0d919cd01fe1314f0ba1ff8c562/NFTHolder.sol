pragma solidity 0.8.16;

import "./IVotingEscrow.sol";
import "./IGauge.sol";
import "./IBribe.sol";
import "./IBaseV1Voter.sol";

import "./IVeDepositor.sol";

import "./PausableUpgradeable.sol";
import "./AccessControlEnumerableUpgradeable.sol";
import "./Initializable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";

contract NFTHolder is
    Initializable,
    AccessControlEnumerableUpgradeable,
    PausableUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // solidly contracts
    IERC20Upgradeable public SOLID;
    IVotingEscrow public votingEscrow;
    IBaseV1Voter public solidlyVoter;

    // monlith contracts
    IVeDepositor public moSolid;
    address public splitter;

    uint256 public tokenID;

    function initialize(
        IERC20Upgradeable _solid,
        IVotingEscrow _votingEscrow,
        IBaseV1Voter _solidlyVoter,
        address admin,
        address pauser,
        address unpauser,
        address setter,
        address operator
    ) public initializer {
        __Pausable_init();
        __AccessControlEnumerable_init();

        SOLID = _solid;
        votingEscrow = _votingEscrow;
        solidlyVoter = _solidlyVoter;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(UNPAUSER_ROLE, unpauser);
        _grantRole(SETTER_ROLE, setter);
        _grantRole(OPERATOR_ROLE, operator);
    }

    function setAddresses(IVeDepositor _moSolid, address _splitter)
        external
        onlyRole(SETTER_ROLE)
    {
        moSolid = _moSolid;
        splitter = _splitter;

        // for merge
        votingEscrow.setApprovalForAll(address(_moSolid), true);

        // for splitting and resetting votes
        votingEscrow.setApprovalForAll(_splitter, true);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(UNPAUSER_ROLE) {
        _unpause();
    }

    function onERC721Received(
        address _operator,
        address _from,
        uint256 _tokenID,
        bytes calldata
    ) external returns (bytes4) {
        // VeDepositor transfers the NFT to this contract so this callback is required
        require(_operator == address(moSolid));

        if (tokenID == 0) {
            tokenID = _tokenID;
        }

        return
            bytes4(
                keccak256("onERC721Received(address,address,uint256,bytes)")
            );
    }

    function detachGauges(address[] memory gaugeAddresses) external {
        require(msg.sender == splitter, "Not Splitter");

        uint256 amount;
        for (uint256 i = 0; i < gaugeAddresses.length; i++) {
            // max withdraw is 1e16 token to avoid large asset transfer
            amount = IGauge(gaugeAddresses[i]).balanceOf(address(this));
            if (amount > 0) {
                if (amount > 1e16) amount = 1e16;
                IGauge(gaugeAddresses[i]).withdrawToken(amount, tokenID);
                IGauge(gaugeAddresses[i]).deposit(amount, 0);
            }
        }
    }

    function reattachGauges(address[] memory gaugeAddresses) external {
        require(msg.sender == splitter, "Not Splitter");

        uint256 amount = 1e16;
        for (uint256 i = 0; i < gaugeAddresses.length; i++) {
            amount = IGauge(gaugeAddresses[i]).balanceOf(address(this));
            if (amount > 0) {
                if (amount > 1e16) amount = 1e16;
                IGauge(gaugeAddresses[i]).withdrawToken(amount, 0);
                IGauge(gaugeAddresses[i]).deposit(amount, tokenID);
            }
        }
    }

    function vote(address[] memory pools, int256[] memory weights)
        external
        onlyRole(OPERATOR_ROLE)
    {
        solidlyVoter.vote(tokenID, pools, weights);
    }

    function getReward(address rewarder, address[] memory tokens) external {
        IBribe(rewarder).getReward(tokenID, tokens);
    }

    function withdrawERC20(address token, address to)
        external
        onlyRole(OPERATOR_ROLE)
    {
        IERC20Upgradeable(token).safeTransfer(
            to,
            IERC20Upgradeable(token).balanceOf(address(this))
        );
    }


    function withdrawNFT(address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        votingEscrow.safeTransferFrom(address(this), to, tokenID);
    }
}

