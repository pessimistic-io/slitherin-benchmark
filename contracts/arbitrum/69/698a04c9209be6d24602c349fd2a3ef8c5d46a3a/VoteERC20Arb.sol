// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                        //
//                                                                                        //
//    ████████████████████████████████████████████████████████████████████████████████    //
//                                                                                        //
//    ████████████████████████████████████████████████████████████████████████████████    //
//                                                                                        //
//    ████████████████████████████████████████████████████████████████████████████████    //
//                                                                                        //
//    ████████████████████████████████████████████████████████████████████████████████    //
//                                                                                        //
//    ██████████████████████████████████████████████████████▀▀▀▀██████████████████████    //
//                                                                                        //
//    ████▌       ███   ████⌐  ╫██   █████   █████⌐  ███▀─        ╙███    ▀███▌  j████    //
//                                                                                        //
//    ████▌  ╟█⌐  ███   ████⌐  ╫██   █████   █████⌐  ██▌   █████▄  └██      ██▌  j████    //
//                                                                                        //
//    ████▌      └▀██   ████⌐  ╫██   █████   █████⌐  ██─  ╟██████   ██   █▄  ╙█  j████    //
//                                                                                        //
//    ████▌  ╟██   ╫█─  ╙███   ███   █████   █████⌐  ███   ▀███▀─  ╓██   ███,    j████    //
//                                                                                        //
//    ████▌       ▄███▄       ▓███      ╟█      ▐█⌐  ████▄       ╓████   █████   j████    //
//                                                                                        //
//    ████████████████████████████████████████████████████████████████████████████████    //
//                                                                                        //
//    ████████████████████████████████████████████████████████████████████████████████    //
//                                                                                        //
//    ████████████████████████████████████████████████████████████████████████████████    //
//                                                                                        //
//    ████▌──└█████¬──██▌──▐███▀▀─    ╙▀███▌──────██▌─────└▀███▌──▐█████───╙██████████    //
//                                                                                        //
//    ████▌    ╙███   ██▌  ▐██└  ╓▓██▄  ▄██▌  j▓▓▓██▌  ▐█▄   ██▌  ▐████─    ╙█████████    //
//                                                                                        //
//    ████▌  }   ▀█   ██▌  ▐█▌  ]███▀▀▀▀▀▀█▌   └└└██▌  └▀╙  ,██▌  ▐███▀  ▓▌  ╙████████    //
//                                                                                        //
//    ████▌  ╟█▌      ██▌  ▐█▌   ███▄▄   ▐█▌   ▄▄▄██▌  ╒   ████▌  ▐██▌   ▀▀   ╟███████    //
//                                                                                        //
//    ████▌  ╟███▄    ██▌  ▐██▌   ╙▀▀─  ▄██▌   ╙╙╙██▌  ╞█   ╙██▌  ▐█▌   ▄▄▄▄   ███████    //
//                                                                                        //
//    █████▄▄██████▄▄▄███▄▄▓█████▄▄▄▄▄▓█████▄▄▄▄▄▄███▄▄███▄▄▄▄██▄▄██▄▄▄██████▄▄▄██████    //
//                                                                                        //
//    ████████████████████████████████████████████████████████████████████████████████    //
//                                                                                        //
//    ████████████████████████████████████████████████████████████████████████████████    //
//                                                                                        //
//    ████████████████████████████████████████████████████████████████████████████████    //
//                                                                                        //
//    ████████████████████████████████████████████████████████████████████████████████    //
//                                                                                        //
//    ███████████████▒████████████████████████████████████████████▀███ ███████████████    //
//                                                                                        //
//    ███████████████⌐███⌐████████████████████████████████████████ ███ ███████████████    //
//                                                                                        //
//    ███████████████⌐██▄▀ ███████████████████████████████████████ ███ ███████████████    //
//                                                                                        //
//    ███████████████⌐███⌐████████████▀╙. .∞▓██▓═` .╙▀████████████ ███ ███████████████    //
//                                                                                        //
//    ███████████████⌐███⌐███████████▄ ¼╙██▀ ,▄ ▀███/  ███████████ ███ ███████████████    //
//                                                                                        //
//    ███████████████⌐███⌐█████████████▄▄, └▀▀▀▀▀ ,▄▄█████████████ ███ ███████████████    //
//                                                                                        //
//    ███████████████⌐██▄▀╥███████████████████████████████████████ ███ ███████████████    //
//                                                                                        //
//    ███████████████⌐███▄▀███████████████████████████████████████,███ ███████████████    //
//                                                                                        //
//    ████████████████████▀███████▀██████████████████████▀███████▀████▓███████████████    //
//                                                                                        //
//    ████████████████████████████████████████████████████████████████████████████████    //
//                                                                                        //
//    ████████████████████████████████████████████████████████████████████████████████    //
//                                                                                        //
//    ████████████████████████████████████████████████████████████████████████████████    //
//                                                                                        //
//    ████████████████████████████████████████████████████████████████████████████████    //
//                                                                                        //
//                                                                                        //
////////////////////////////////////////////////////////////////////////////////////////////

import "./IThirdwebContract.sol";

// Governance
import "./GovernorUpgradeable.sol";
import "./IVotesUpgradeable.sol";
import "./GovernorSettingsUpgradeable.sol";
import "./GovernorCountingSimpleUpgradeable.sol";
import "./GovernorVotesUpgradeable.sol";
import "./GovernorVotesQuorumFractionUpgradeable.sol";

// Meta transactions
import "./ERC2771ContextUpgradeable.sol";


contract VoteERC20Arb is
    Initializable,
    IThirdwebContract,
    ERC2771ContextUpgradeable,
    GovernorUpgradeable,
    GovernorSettingsUpgradeable,
    GovernorCountingSimpleUpgradeable,
    GovernorVotesUpgradeable,
    GovernorVotesQuorumFractionUpgradeable
{
    bytes32 private constant MODULE_TYPE = bytes32("VoteERC20");
    uint256 private constant VERSION = 1;

    string public contractURI;
    uint256 public proposalIndex;

   

    struct Proposal {
        uint256 proposalId;
        address proposer;
        address[] targets;
        uint256[] values;
        string[] signatures;
        bytes[] calldatas;
        uint256 startBlock;
        uint256 endBlock;
        string description;
    }

    /// @dev proposal index => Proposal
    mapping(uint256 => Proposal) public proposals;

    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    /// @dev Initiliazes the contract, like a constructor.
    function initialize(
        string memory _name,
        string memory _contractURI,
        address[] memory _trustedForwarders,
        address _token,
        uint256 _initialVotingDelay,
        uint256 _initialVotingPeriod,
        uint256 _initialProposalThreshold,
        uint256 _initialVoteQuorumFraction
    ) external initializer {
        // Initialize inherited contracts, most base-like -> most derived.
        __ERC2771Context_init(_trustedForwarders);
        __Governor_init(_name);
        __GovernorSettings_init(_initialVotingDelay, _initialVotingPeriod, _initialProposalThreshold);
        __GovernorVotes_init(IVotesUpgradeable(_token));
        __GovernorVotesQuorumFraction_init(_initialVoteQuorumFraction);

        // Initialize this contract's state.
        contractURI = _contractURI;
    }


    /// @dev Returns the module type of the contract.
    function contractType() external pure returns (bytes32) {
        return MODULE_TYPE;
    }

    /// @dev Returns the version of the contract.
    function contractVersion() public pure override returns (uint8) {
        return uint8(VERSION);
    }

    /**
     * @dev See {IGovernor-propose}.
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public virtual  override returns (uint256 proposalId) {
        proposalId = super.propose(targets, values, calldatas, description);

        proposals[proposalIndex] = Proposal({
            proposalId: proposalId,
            proposer: _msgSender(),
            targets: targets,
            values: values,
            signatures: new string[](targets.length),
            calldatas: calldatas,
            startBlock: proposalSnapshot(proposalId),
            endBlock: proposalDeadline(proposalId),
            description: description
        });

        proposalIndex += 1;
    }

    /// @dev Returns all proposals made.
    function getAllProposals() external view returns (Proposal[] memory allProposals) {
        uint256 nextProposalIndex = proposalIndex;

        allProposals = new Proposal[](nextProposalIndex);
        for (uint256 i = 0; i < nextProposalIndex; i += 1) {
            allProposals[i] = proposals[i];
        }
    }

    function setContractURI(string calldata uri) external onlyGovernance {
        contractURI = uri;
    }

    function proposalThreshold()
        public
        view
        override(GovernorUpgradeable, GovernorSettingsUpgradeable)
        returns (uint256)
    {
        return GovernorSettingsUpgradeable.proposalThreshold();
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IERC721ReceiverUpgradeable).interfaceId || super.supportsInterface(interfaceId);
    }

    function _msgSender()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (address sender)
    {
        return ERC2771ContextUpgradeable._msgSender();
    }

    function _msgData()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (bytes calldata)
    {
        return ERC2771ContextUpgradeable._msgData();
    }



    function castVote(uint256 proposalId, uint8 support) public virtual  override returns (uint256) {
        address voter = _msgSender();
        return _castVote(proposalId, voter, support, "");
    }

    function castVoteWithReason(
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) public virtual  override returns (uint256) {
        address voter = _msgSender();
        return _castVote(proposalId, voter, support, reason);
    }

    function castVoteWithReasonAndParams(
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes memory params
    ) public virtual  override returns (uint256) {
        address voter = _msgSender();
        return _castVote(proposalId, voter, support, reason, params);
    }

    function castVoteBySig(
        uint256 proposalId,
        uint8 support,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual  override returns (uint256) {
        address voter = ECDSAUpgradeable.recover(
            _hashTypedDataV4(keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support))),
            v,
            r,
            s
        );
        return _castVote(proposalId, voter, support, "");
    }

    /**
     * @dev See {IGovernor-castVoteWithReasonAndParamsBySig}.
     */
    function castVoteWithReasonAndParamsBySig(
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes memory params,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual  override returns (uint256) {
        address voter = ECDSAUpgradeable.recover(
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        EXTENDED_BALLOT_TYPEHASH,
                        proposalId,
                        support,
                        keccak256(bytes(reason)),
                        keccak256(params)
                    )
                )
            ),
            v,
            r,
            s
        );

        return _castVote(proposalId, voter, support, reason, params);
    }

}
