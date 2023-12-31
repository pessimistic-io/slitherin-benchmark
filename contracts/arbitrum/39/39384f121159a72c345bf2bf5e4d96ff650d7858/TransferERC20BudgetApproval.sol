// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.7;

import "./CommonBudgetApproval.sol";
import "./BytesLib.sol";
import "./IERC20.sol";

import "./IBudgetApprovalExecutee.sol";

contract TransferERC20BudgetApproval is CommonBudgetApproval {
    using BytesLib for bytes;

    bool public allowAllAddresses;
    mapping(address => bool) public addressesMapping;
    bool public allowAllTokens;
    address public token;
    bool public allowAnyAmount;
    uint256 public totalAmount;

    // v2
    uint256[] public toTeamIds;
    mapping(uint256 => bool) public toTeamIdsMapping;

    event AllowTeam(uint256 indexed teamId);
    event ExecuteTransferERC20Transaction(
        uint256 indexed id,
        address indexed executor,
        address indexed toAddress,
        address token,
        uint256 amount
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        InitializeParams calldata params,
        bool _allowAllAddresses,
        address[] memory _toAddresses,
        bool _allowAllTokens,
        address _token,
        bool _allowAnyAmount,
        uint256 _totalAmount,
        // v2
        uint256[] memory _toTeamIds
    ) external initializer {
        __BudgetApproval_init(params);

        allowAllAddresses = _allowAllAddresses;
        for (uint256 i = 0; i < _toAddresses.length; i++) {
            _addToAddress(_toAddresses[i]);
        }

        for (uint256 i = 0; i < _toTeamIds.length; i++) {
            _addToTeam(_toTeamIds[i]);
        }

        allowAllTokens = _allowAllTokens;
        token = _token;
        allowAnyAmount = _allowAnyAmount;
        totalAmount = _totalAmount;
    }

    function name() external pure override virtual returns (string memory) {
        return "Transfer ERC20 Budget Approval";
    }

    function executeParams() external pure override virtual returns (string[] memory) {
        string[] memory arr = new string[](3);
        arr[0] = "address token";
        arr[1] = "address to";
        arr[2] = "uint256 value";
        return arr;
    }

    function _execute(uint256 transactionId, bytes memory data)
        internal
        override
        virtual
    {
        (address _token, address to, uint256 value) = abi.decode(
            data,
            (address, address, uint256)
        );
        bytes memory executeData = abi.encodeWithSelector(
            IERC20.transfer.selector,
            to,
            value
        );
        bool _allowAnyAmount = allowAnyAmount;
        uint256 _totalAmount = totalAmount;

        IBudgetApprovalExecutee(executee()).executeByBudgetApproval(
            _token,
            executeData,
            0
        );

        require(
            allowAllAddresses ||
                addressesMapping[to] ||
                _checkIsToTeamsMember(to),
            "Recipient not whitelisted in budget"
        );
        require(
            allowAllTokens || token == _token,
            "Token not whitelisted in budget"
        );
        require(
            _allowAnyAmount || value <= _totalAmount,
            "Exceeded max budget transferable amount"
        );

        if (!_allowAnyAmount) {
            totalAmount = _totalAmount - value;
        }
        emit ExecuteTransferERC20Transaction(
            transactionId,
            msg.sender,
            to,
            _token,
            value
        );
    }

    function _addToAddress(address to) internal {
        require(
            !addressesMapping[to],
            "Duplicated address in target address list"
        );
        addressesMapping[to] = true;
        emit AllowAddress(to);
    }

    function _checkIsToTeamsMember(address to) internal view returns (bool) {
        uint256 _toTeamIdsLength = toTeamIds.length;
        address[] memory toArray = new address[](_toTeamIdsLength);
        for (uint256 i = 0; i < _toTeamIdsLength; i++) {
            toArray[i] = to;
        }

        uint256[] memory balances = ITeam(team()).balanceOfBatch(
            toArray,
            toTeamIds
        );

        for (uint256 i = 0; i < balances.length; i++) {
            if (balances[i] > 0) {
                return true;
            }
        }
        return false;
    }

    function _addToTeam(uint256 teamId) internal {
        require(
            !toTeamIdsMapping[teamId],
            "Duplicated team in target team list"
        );
        toTeamIdsMapping[teamId] = true;
        toTeamIds.push(teamId);
        emit AllowTeam(teamId);
    }

    function toTeamsLength() public view returns (uint256) {
        return toTeamIds.length;
    }
}

