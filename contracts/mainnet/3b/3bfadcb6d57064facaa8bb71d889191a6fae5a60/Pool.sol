// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./GovernorProposals.sol";
import "./IService.sol";
import "./IPool.sol";
import "./IToken.sol";
import "./ITGE.sol";
import "./ICustomProposal.sol";
import "./IRecordsRegistry.sol";
import "./IRecordsRegistry.sol";
import "./ExceptionsLibrary.sol";

/// @dev These contracts are instances of on-chain implementations of user companies. The shareholders of the companies work with them, their addresses are used in the Registry contract as tags that allow obtaining additional legal information (before the purchase of the company by the client). They store legal data (after the purchase of the company by the client). Among other things, the contract is also the owner of the Token and TGE contracts.
/// @dev There can be an unlimited number of such contracts, including for one company owner. The contract can be in three states: 1) the company was created by the administrator, a record of it is stored in the Registry, but the contract has not yet been deployed and does not have an owner (buyer) 2) the contract is deployed, the company has an owner, but there is not yet a successful (softcap primary TGE), in this state its owner has the exclusive right to recreate the TGE in case of their failure (only one TGE can be launched at the same time) 3) the primary TGE ended successfully, softcap is assembled - the company has received the status of DAO.    The owner no longer has any exclusive rights, all the actions of the company are carried out through the creation and execution of propousals after voting. In this status, the contract is also a treasury - it stores the company's values in the form of ETH and/or ERC20 tokens.
contract Pool is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    GovernorProposals,
    IPool
{
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using AddressUpgradeable for address payable;
    /// @dev The company's trade mark, label, brand name. It also acts as the Name of all the Governance tokens created for this pool.
    string public trademark;

    /// @dev When a buyer acquires a company, its record disappears from the Registry contract, but before that, the company's legal data is copied to this variable.
    ICompaniesRegistry.CompanyInfo public companyInfo;

    /// @dev Mapping for Governance Token. There can be only one valid Governance token.
    mapping(IToken.TokenType => address) public tokens;

    /// @dev last proposal id for address. This method returns the proposal Id for the last proposal created by the specified address.
    mapping(address => uint256) public lastProposalIdForAddress;

    /// @dev mapping for creation block
    mapping(uint256 => uint256) public proposalCreatedAt;

    /// @dev A list of tokens belonging to this pool. There can be only one valid Governance token and several Preference tokens with diffrent settings.
    mapping(IToken.TokenType => address[]) public tokensFullList;

    /// @dev token type by address
    mapping(address => IToken.TokenType) public tokenTypeByAddress;

    /// @dev pool secretary list
    EnumerableSetUpgradeable.AddressSet poolSecretary;

    /// @dev last executed proposal Id
    uint256 public lastExecutedProposalId;

    /// @dev mapping for proposalId to TGE address
    mapping(uint256 => address) public proposalIdToTGE;

    /// @dev pool executor list
    EnumerableSetUpgradeable.AddressSet poolExecutor;

    /// @dev Operating Agreement Url
    string public OAurl;

    // EVENTS

    // MODIFIER

    /// @dev Is executed when the main contract is applied. It is used to transfer control of Registry and deployable user contracts for the final configuration of the company.
    modifier onlyService() {
        require(msg.sender == address(service), ExceptionsLibrary.NOT_SERVICE);
        _;
    }

    modifier onlyTGEFactory() {
        require(
            msg.sender == address(service.tgeFactory()),
            ExceptionsLibrary.NOT_TGE_FACTORY
        );
        _;
    }

    modifier onlyServiceAdmin() {
        require(
            service.hasRole(service.ADMIN_ROLE(), msg.sender),
            ExceptionsLibrary.NOT_SERVICE_OWNER
        );
        _;
    }

    // INITIALIZER AND CONFIGURATOR

    /// @custom:oz-upgrades-unsafe-allow constructor

    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialization of a new pool and placement of user settings and data (including legal ones) in it
     * @param companyInfo_ Company info
     */
    function initialize(
        ICompaniesRegistry.CompanyInfo memory companyInfo_
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        service = IService(msg.sender);
        companyInfo = companyInfo_;
    }

    /**
     * @dev set New Owner With Settings after company purchased
     * @param newowner New Pool owner
     * @param trademark_ trademark_
     * @param governanceSettings_ governance Settings
     */
    function setNewOwnerWithSettings(
        address newowner,
        string memory trademark_,
        NewGovernanceSettings memory governanceSettings_
    ) external onlyService {
        _transferOwnership(address(newowner));
        trademark = trademark_;
        _setGovernanceSettings(governanceSettings_);
    }

    /**
     * @dev set New Owner With Settings after company purchased
     * @param governanceSettings_ governance Settings
     * @param secretary secretary address list
     * @param executor executor address list
     */
    function setSettings(
        NewGovernanceSettings memory governanceSettings_,
        address[] memory secretary,
        address[] memory executor
    ) external {
        //only tgeFactory or pool
        require(
            msg.sender == address(service.tgeFactory()) ||
                msg.sender == address(this),
            ExceptionsLibrary.NOT_TGE_FACTORY
        );
        if (msg.sender == address(service.tgeFactory())) {
            if (address(getGovernanceToken()) != address(0)) {
                require(!isDAO(), ExceptionsLibrary.IS_DAO);
                require(
                    ITGE(getGovernanceToken().lastTGE()).state() !=
                        ITGE.State.Active,
                    ExceptionsLibrary.ACTIVE_TGE_EXISTS
                );
            }
        }
        _setGovernanceSettings(governanceSettings_);

        address[] memory values = poolSecretary.values();
        for (uint256 i = 0; i < values.length; i++) {
            poolSecretary.remove(values[i]);
        }

        for (uint256 i = 0; i < secretary.length; i++) {
            poolSecretary.add(secretary[i]);
        }

        values = poolExecutor.values();
        for (uint256 i = 0; i < values.length; i++) {
            poolExecutor.remove(values[i]);
        }

        for (uint256 i = 0; i < executor.length; i++) {
            poolExecutor.add(secretary[i]);
        }
    }

    /**
     * @dev sets new companyInfo and Operating Agreement Url
     * @param _jurisdiction Operating Agreement Url
     * @param _entityType Operating Agreement Url
     * @param _ein Operating Agreement Url
     * @param _dateOfIncorporation Operating Agreement Url
     * @param _OAuri Operating Agreement Url
     */
    function setCompanyInfo(
        uint256 _jurisdiction,
        uint256 _entityType,
        string memory _ein,
        string memory _dateOfIncorporation,
        string memory _OAuri
    ) external {
        require(
            msg.sender == address(service.registry()),
            ExceptionsLibrary.NOT_REGISTRY
        );
        companyInfo.jurisdiction = _jurisdiction;
        companyInfo.entityType = _entityType;
        companyInfo.ein = _ein;
        companyInfo.dateOfIncorporation = _dateOfIncorporation;
        OAurl = _OAuri;
    }

    // RECEIVE
    /// @dev Method for receiving an Ethereum contract that issues an event.
    receive() external payable {}

    // PUBLIC FUNCTIONS

    /**
     * @dev With this method, the owner of the Governance token of the pool can vote for one of the active propo-nodes, specifying its number and the value of the vote (for or against). One user can vote only once for one proposal with all the available balance that is in delegation at once.
     * @param proposalId Pool proposal ID
     * @param support Against or for
     */
    function castVote(
        uint256 proposalId,
        bool support
    ) external nonReentrant whenNotPaused {
        _castVote(proposalId, support);

        service.registry().log(
            msg.sender,
            address(this),
            0,
            abi.encodeWithSelector(IPool.castVote.selector, proposalId, support)
        );
    }

    // RESTRICTED PUBLIC FUNCTIONS

    /**
     * @dev Adding a new entry about the deployed token contract to the list of tokens related to the pool.
     * @param token_ Token address
     * @param tokenType_ Token type
     */
    function setToken(
        address token_,
        IToken.TokenType tokenType_
    ) external onlyTGEFactory {
        require(token_ != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        if (tokenExists(IToken(token_))) return;
        if (tokenType_ == IToken.TokenType.Governance) {
            // Check that there is no governance tokens or tge failed
            require(
                address(getGovernanceToken()) == address(0) ||
                    ITGE(getGovernanceToken().getTGEList()[0]).state() ==
                    ITGE.State.Failed,
                ExceptionsLibrary.GOVERNANCE_TOKEN_EXISTS
            );
            tokens[IToken.TokenType.Governance] = token_;
            if (tokensFullList[tokenType_].length > 0) {
                tokensFullList[tokenType_].pop();
            }
        }
        tokensFullList[tokenType_].push(token_);
        tokenTypeByAddress[address(token_)] = tokenType_;
    }

    /**
     * @dev set value to mapping Proposal IdTo TGE
     * @param tge tge address
     */
    function setProposalIdToTGE(address tge) external onlyTGEFactory {
        proposalIdToTGE[lastExecutedProposalId] = tge;
    }

    /**
     * @dev Execute proposal
     * @param proposalId Proposal ID
     */
    function executeProposal(uint256 proposalId) external whenNotPaused {
        require(
            isValidExecutor(msg.sender),
            ExceptionsLibrary.NOT_VALID_EXECUTOR
        );

        lastExecutedProposalId = proposalId;
        _executeProposal(proposalId, service);

        service.registry().log(
            msg.sender,
            address(this),
            0,
            abi.encodeWithSelector(IPool.executeProposal.selector, proposalId)
        );
    }

    /**
     * @dev Cancel proposal, callable only by Service
     * @param proposalId Proposal ID
     */
    function cancelProposal(uint256 proposalId) external onlyService {
        _cancelProposal(proposalId);
    }

    /**
     * @dev Creating a proposal and assigning it a unique identifier to store in the list of proposals in the Governor contract.
     * @param core Proposal core data
     * @param meta Proposal meta data
     */
    function propose(
        address proposer,
        uint256 proposeType,
        IGovernor.ProposalCoreData memory core,
        IGovernor.ProposalMetaData memory meta
    ) external returns (uint256 proposalId) {
        require(
            msg.sender == address(service.customProposal()) &&
                isValidProposer(proposer),
            ExceptionsLibrary.NOT_VALID_PROPOSER
        );

        core.quorumThreshold = quorumThreshold;
        core.decisionThreshold = decisionThreshold;
        core.executionDelay = executionDelays[meta.proposalType];
        uint256 proposalId_ = _propose(
            core,
            meta,
            votingDuration,
            votingStartDelay
        );
        lastProposalIdByType[proposeType] = proposalId_;

        _setLastProposalIdForAddress(proposer, proposalId_);

        service.registry().log(
            msg.sender,
            address(this),
            0,
            abi.encodeWithSelector(
                IPool.propose.selector,
                proposer,
                proposeType,
                core,
                meta
            )
        );

        return proposalId_;
    }

    /**
     * @dev Transfers funds from treasury if the pool is not yeta  DAO
     * @param to receiver addresss
     * @param amount transfer amount
     * @param unitOfAccount unitOfAccount (token contract address or address(0) for eth)
     */
    function transferByOwner(
        address to,
        uint256 amount,
        address unitOfAccount
    ) external onlyOwner {
        //only if pool is yet DAO
        require(!isDAO(), ExceptionsLibrary.IS_DAO);

        if (unitOfAccount == address(0)) {
            require(
                address(this).balance >= amount,
                ExceptionsLibrary.WRONG_AMOUNT
            );

            (bool success, ) = payable(to).call{value: amount}("");
            require(success, ExceptionsLibrary.WRONG_AMOUNT);
        } else {
            require(
                IERC20Upgradeable(unitOfAccount).balanceOf(address(this)) >=
                    amount,
                ExceptionsLibrary.WRONG_AMOUNT
            );

            IERC20Upgradeable(unitOfAccount).safeTransferFrom(
                msg.sender,
                to,
                amount
            );
        }
    }

    /**
     * @dev Execute custom tx if the pool is not yet a  DAO
     * @param target receiver addresss
     * @param value transfer amount
     * @param data input data of the transaction
     */
    function customTxByOwner(
        address target,
        uint256 value,
        bytes calldata data
    ) external onlyOwner {
        //only if pool is yet DAO
        require(!isDAO(), ExceptionsLibrary.IS_DAO);

        target.functionCallWithValue(data, value);
    }

    // PUBLIC VIEW FUNCTIONS

    /**
     * @dev Getter showing whether this company has received the status of a DAO as a result of the successful completion of the primary TGE (that is, launched by the owner of the company and with the creation of a new Governance token). After receiving the true status, it is not transferred back. This getter is responsible for the basic logic of starting a contract as managed by token holders.
     * @return Is any governance TGE successful
     */
    function isDAO() public view returns (bool) {
        if (address(getGovernanceToken()) == address(0)) {
            return false;
        } else {
            return getGovernanceToken().isPrimaryTGESuccessful();
        }
    }

    /**
     * @dev Return pool owner
     * @return Owner address
     */
    function owner()
        public
        view
        override(IPool, OwnableUpgradeable)
        returns (address)
    {
        return super.owner();
    }

    /// @dev This getter is needed in order to return a Token contract addresses depending on the type of token requested (Governance or Preference).
    function getTokens(
        IToken.TokenType tokenType
    ) external view returns (address[] memory) {
        return tokensFullList[tokenType];
    }

    /// @dev This getter returns current Governance Token For this Pool
    function getGovernanceToken() public view returns (IToken) {
        return IToken(tokens[IToken.TokenType.Governance]);
    }

    /**
     * @dev Getter checks token exists for this pool
     * @return bool
     */
    function tokenExists(IToken token) public view returns (bool) {
        return
            tokenTypeByAddress[address(token)] == IToken.TokenType.None
                ? false
                : true;
    }

    /// @dev This getter to show list of current pool Secretary
    function getPoolSecretary() external view returns (address[] memory) {
        return poolSecretary.values();
    }

    /// @dev This getter to show list of current pool executor
    function getPoolExecutor() external view returns (address[] memory) {
        return poolExecutor.values();
    }

    /// @dev This getter shows if address is pool Secretary
    function isPoolSecretary(address account) public view returns (bool) {
        return poolSecretary.contains(account);
    }

    /// @dev This getter shows if address is pool executor
    function isPoolExecutor(address account) public view returns (bool) {
        return poolExecutor.contains(account);
    }

    /// @dev This getter check if address can propose
    function isValidProposer(address account) public view returns (bool) {
        if (
            _getCurrentVotes(account) >= proposalThreshold ||
            isPoolSecretary(account) ||
            service.hasRole(service.SERVICE_MANAGER_ROLE(), msg.sender)
        ) return true;

        return false;
    }

    /// @dev This getter check if address can execute ballot
    function isValidExecutor(address account) public view returns (bool) {
        if (
            poolExecutor.length() == 0 ||
            isPoolExecutor(account) ||
            service.hasRole(service.SERVICE_MANAGER_ROLE(), account)
        ) return true;

        return false;
    }

    /// @dev This getter returns if Last Proposal By Type is Active
    function isLastProposalIdByTypeActive(
        uint256 type_
    ) public view returns (bool) {
        if (proposalState(lastProposalIdByType[type_]) == ProposalState.Active)
            return true;

        return false;
    }

    /// @dev This getter validate Governance Settings
    function validateGovernanceSettings(
        NewGovernanceSettings memory settings
    ) external pure {
        _validateGovernanceSettings(settings);
    }

    /// @dev This getter returns if available Votes For Proposal by Id
    function availableVotesForProposal(
        uint256 proposalId
    ) external view returns (uint256) {
        if (proposals[proposalId].vote.startBlock - 1 < block.number)
            return
                _getBlockTotalVotes(proposals[proposalId].vote.startBlock - 1);
        else return _getBlockTotalVotes(block.number - 1);
    }

    // INTERNAL FUNCTIONS

    function _afterProposalCreated(uint256 proposalId) internal override {
        service.addProposal(proposalId);
    }

    /**
     * @dev Function that gets amount of votes for given account
     * @param account Account's address
     * @return Amount of votes
     */
    function _getCurrentVotes(address account) internal view returns (uint256) {
        return getGovernanceToken().getVotes(account);
    }

    /**
     * @dev Function that returns the total amount of votes in the pool in block
     * @param blocknumber blocknumber
     * @return Amount of votes
     */
    function _getBlockTotalVotes(
        uint256 blocknumber
    ) internal view override returns (uint256) {
        return
            IToken(tokens[IToken.TokenType.Governance]).getPastTotalSupply(
                blocknumber
            );
    }

    /**
     * @dev Function that gets amount of votes for given account at given block
     * @param account Account's address
     * @param blockNumber Block number
     * @return Account's votes at given block
     */
    function _getPastVotes(
        address account,
        uint256 blockNumber
    ) internal view override returns (uint256) {
        return getGovernanceToken().getPastVotes(account, blockNumber);
    }

    /**
     * @dev This function stores the proposal id for the last proposal created by the proposer address.
     * @param proposer Proposer's address
     * @param proposalId Proposal id
     */
    function _setLastProposalIdForAddress(
        address proposer,
        uint256 proposalId
    ) internal override {
        lastProposalIdForAddress[proposer] = proposalId;
    }
}

