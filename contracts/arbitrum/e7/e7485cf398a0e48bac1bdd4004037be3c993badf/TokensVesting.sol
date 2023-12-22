// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./EnumerableSet.sol";
import "./AccessControlEnumerable.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./ITokensVesting.sol";

contract TokensVesting is
    ReentrancyGuard,
    AccessControlEnumerable,
    ITokensVesting
{
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    uint256 public constant DEFAULT_BASIS = 30 days;

    IERC20 public immutable token;

    VestingInfo[] private _beneficiaries;
    mapping(address => EnumerableSet.UintSet)
        private _beneficiaryAddressIndexes;
    mapping(bytes32 => EnumerableSet.UintSet) private _beneficiaryRoleIndexes;
    EnumerableSet.UintSet private _revokedBeneficiaryIndexes;

    constructor(address _token) {
        require(
            _token != address(0),
            "TokensVesting::constructor: _token is the zero address!"
        );
        token = IERC20(_token);

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(OPERATOR_ROLE, msg.sender);
    }

    function addBeneficiaries(
        VestingInfo[] calldata infos
    ) external onlyRole(OPERATOR_ROLE) returns (uint256 _index) {
        for (uint256 index = 0; index < infos.length; index++) {
            _validateVestingInfo(infos[index]);
        }
        for (uint256 index = 0; index < infos.length; index++) {
            _index = _addBeneficiary(infos[index]);
        }
    }

    function addBeneficiary(
        VestingInfo calldata info
    ) external onlyRole(OPERATOR_ROLE) returns (uint256) {
        _validateVestingInfo(info);
        return _addBeneficiary(info);
    }

    function releaseAll() external onlyRole(OPERATOR_ROLE) {
        _releaseAll();
    }

    function releaseParticipant(
        Participant participant
    ) external onlyRole(OPERATOR_ROLE) {
        _releaseParticipant(participant);
    }

    function releaseMyTokens() external nonReentrant {
        require(
            _beneficiaryAddressIndexes[msg.sender].length() > 0,
            "TokensVesting: sender is not in vesting plan"
        );

        for (
            uint256 _index = 0;
            _index < _beneficiaryAddressIndexes[msg.sender].length();
            _index++
        ) {
            uint256 _beneficiaryIndex = _beneficiaryAddressIndexes[msg.sender]
                .at(_index);
            VestingInfo storage _info = _beneficiaries[_beneficiaryIndex];

            uint256 _unreleaseAmount = _releasableAmount(_beneficiaryIndex);
            if (_unreleaseAmount > 0) {
                _info.releasedAmount = _info.releasedAmount + _unreleaseAmount;
                token.safeTransfer(msg.sender, _unreleaseAmount);
                emit TokensReleased(msg.sender, _unreleaseAmount);
            }
        }
    }

    function releaseTokensOfRole(
        bytes32 role,
        uint256 amount
    ) external nonReentrant {
        require(
            hasRole(role, msg.sender),
            "TokensVesting: unauthorized sender"
        );
        require(
            releasableAmountOfRole(role) > 0,
            "TokensVesting: no tokens are due"
        );
        require(
            releasableAmountOfRole(role) >= amount,
            "TokensVesting: insufficient amount"
        );

        _releaseTokensOfRole(role, amount, msg.sender);
    }

    function release(uint256 index) external nonReentrant {
        require(
            _beneficiaries[index].beneficiary != address(0),
            "TokensVesting: bad index"
        );
        require(
            hasRole(OPERATOR_ROLE, msg.sender) ||
                _beneficiaries[index].beneficiary == msg.sender,
            "TokensVesting: unauthorized sender"
        );

        _release(index, _beneficiaries[index].beneficiary);
    }

    function revokeTokensOfParticipant(
        Participant participant
    ) external onlyRole(OPERATOR_ROLE) {
        for (uint256 _index = 0; _index < _beneficiaries.length; _index++) {
            if (_beneficiaries[_index].participant == participant) {
                _revoke(_index);
            }
        }
    }

    function revokeTokensOfAddress(
        address beneficiary
    ) external onlyRole(OPERATOR_ROLE) {
        for (
            uint256 _index = 0;
            _index < _beneficiaryAddressIndexes[beneficiary].length();
            _index++
        ) {
            uint256 _addressIndex = _beneficiaryAddressIndexes[beneficiary].at(
                _index
            );
            _revoke(_addressIndex);
        }
    }

    function revokeTokensOfRole(bytes32 role) external onlyRole(OPERATOR_ROLE) {
        for (
            uint256 _index = 0;
            _index < _beneficiaryRoleIndexes[role].length();
            _index++
        ) {
            uint256 _roleIndex = _beneficiaryRoleIndexes[role].at(_index);
            _revoke(_roleIndex);
        }
    }

    function revoke(uint256 index) external onlyRole(OPERATOR_ROLE) {
        _revoke(index);
    }

    function releasableAmount() public view returns (uint256 _amount) {
        for (uint256 _index = 0; _index < _beneficiaries.length; _index++) {
            _amount += _releasableAmount(_index);
        }
    }

    function releasableAmountOfParticipant(
        Participant participant
    ) public view returns (uint256 _amount) {
        for (uint256 _index = 0; _index < _beneficiaries.length; _index++) {
            if (_beneficiaries[_index].participant == participant) {
                _amount += _releasableAmount(_index);
            }
        }
    }

    function releasableAmountOfAddress(
        address beneficiary
    ) public view returns (uint256 _amount) {
        for (
            uint256 _index = 0;
            _index < _beneficiaryAddressIndexes[beneficiary].length();
            _index++
        ) {
            uint256 _addressIndex = _beneficiaryAddressIndexes[beneficiary].at(
                _index
            );
            _amount += _releasableAmount(_addressIndex);
        }
    }

    function releasableAmountOfRole(
        bytes32 role
    ) public view returns (uint256 _amount) {
        for (
            uint256 _index = 0;
            _index < _beneficiaryRoleIndexes[role].length();
            _index++
        ) {
            uint256 _roleIndex = _beneficiaryRoleIndexes[role].at(_index);
            _amount += _releasableAmount(_roleIndex);
        }
    }

    function releasableAmountAt(
        uint256 index
    ) public view returns (uint256 _amount) {
        return _releasableAmount(index);
    }

    function totalAmount() public view returns (uint256 _amount) {
        for (uint256 _index = 0; _index < _beneficiaries.length; _index++) {
            _amount += _beneficiaries[_index].totalAmount;
        }
    }

    function totalAmountOfParticipant(
        Participant participant
    ) public view returns (uint256 _amount) {
        for (uint256 _index = 0; _index < _beneficiaries.length; _index++) {
            if (_beneficiaries[_index].participant == participant) {
                _amount += _beneficiaries[_index].totalAmount;
            }
        }
    }

    function totalAmountOfAddress(
        address beneficiary
    ) public view returns (uint256 _amount) {
        for (uint256 _index = 0; _index < _beneficiaries.length; _index++) {
            if (_beneficiaries[_index].beneficiary == beneficiary) {
                _amount += _beneficiaries[_index].totalAmount;
            }
        }
    }

    function totalAmountOfRole(
        bytes32 role
    ) public view returns (uint256 _amount) {
        for (uint256 _index = 0; _index < _beneficiaries.length; _index++) {
            if (_beneficiaries[_index].role == role) {
                _amount += _beneficiaries[_index].totalAmount;
            }
        }
    }

    function totalAmountAt(uint256 index) public view returns (uint256) {
        return _beneficiaries[index].totalAmount;
    }

    function releasedAmount() public view returns (uint256 _amount) {
        for (uint256 _index = 0; _index < _beneficiaries.length; _index++) {
            _amount += _beneficiaries[_index].releasedAmount;
        }
    }

    function releasedAmountOfParticipant(
        Participant participant
    ) public view returns (uint256 _amount) {
        for (uint256 _index = 0; _index < _beneficiaries.length; _index++) {
            if (_beneficiaries[_index].participant == participant) {
                _amount += _beneficiaries[_index].releasedAmount;
            }
        }
    }

    function releasedAmountOfAddress(
        address beneficiary
    ) public view returns (uint256 _amount) {
        for (uint256 _index = 0; _index < _beneficiaries.length; _index++) {
            if (_beneficiaries[_index].beneficiary == beneficiary) {
                _amount += _beneficiaries[_index].releasedAmount;
            }
        }
    }

    function releasedAmountOfRole(
        bytes32 role
    ) public view returns (uint256 _amount) {
        for (uint256 _index = 0; _index < _beneficiaries.length; _index++) {
            if (_beneficiaries[_index].role == role) {
                _amount += _beneficiaries[_index].releasedAmount;
            }
        }
    }

    function releasedAmountAt(uint256 index) public view returns (uint256) {
        return _beneficiaries[index].releasedAmount;
    }

    function vestingInfoAt(
        uint256 index
    ) public view returns (VestingInfo memory) {
        return _beneficiaries[index];
    }

    function indexesOfBeneficiary(
        address beneficiary
    ) public view returns (uint256[] memory) {
        return _beneficiaryAddressIndexes[beneficiary].values();
    }

    function indexesOfRole(
        bytes32 role
    ) public view returns (uint256[] memory) {
        return _beneficiaryRoleIndexes[role].values();
    }

    function revokedIndexes() public view returns (uint256[] memory) {
        return _revokedBeneficiaryIndexes.values();
    }

    function _addBeneficiary(
        VestingInfo calldata info
    ) private returns (uint256 _index) {
        if (info.beneficiary != address(0)) {
            VestingInfo storage _info = _beneficiaries.push();
            _info.beneficiary = info.beneficiary;
            _info.genesisTimestamp = info.genesisTimestamp;
            _info.totalAmount = info.totalAmount;
            _info.tgeAmount = info.tgeAmount;
            _info.basis = info.basis > 0 ? info.basis : DEFAULT_BASIS;
            _info.cliff = info.cliff;
            _info.duration = info.duration;
            _info.participant = info.participant;
            _info.releasedAmount = info.releasedAmount;

            _index = _beneficiaries.length - 1;

            require(
                _beneficiaryAddressIndexes[info.beneficiary].add(_index),
                "TokensVesting: Duplicated index"
            );

            emit BeneficiaryAddressAdded(
                info.beneficiary,
                info.totalAmount,
                info.participant
            );
        } else {
            VestingInfo storage _info = _beneficiaries.push();
            _info.role = info.role;
            _info.genesisTimestamp = info.genesisTimestamp;
            _info.totalAmount = info.totalAmount;
            _info.tgeAmount = info.tgeAmount;
            _info.basis = info.basis > 0 ? info.basis : DEFAULT_BASIS;
            _info.cliff = info.cliff;
            _info.duration = info.duration;
            _info.participant = info.participant;
            _info.releasedAmount = info.releasedAmount;

            _index = _beneficiaries.length - 1;

            require(
                _beneficiaryRoleIndexes[info.role].add(_index),
                "TokensVesting: Duplicated index"
            );

            emit BeneficiaryRoleAdded(
                info.role,
                info.totalAmount,
                info.participant
            );
        }
    }

    function _vestedAmount(uint256 index) private view returns (uint256) {
        VestingInfo storage _info = _beneficiaries[index];

        if (block.timestamp < _info.genesisTimestamp) {
            return 0;
        }

        uint256 _elapsedTime = block.timestamp - _info.genesisTimestamp;
        if (_elapsedTime < _info.cliff) {
            return _info.tgeAmount;
        }

        if (_elapsedTime >= _info.cliff + _info.duration) {
            return _info.totalAmount;
        }

        uint256 _releaseMilestones = (_elapsedTime - _info.cliff) /
            _info.basis +
            1;
        uint256 _totalReleaseMilestones = (_info.duration + _info.basis - 1) /
            _info.basis +
            1;

        if (_releaseMilestones >= _totalReleaseMilestones) {
            return _info.totalAmount;
        }

        // _totalReleaseMilestones > 1
        uint256 _linearVestingAmount = _info.totalAmount - _info.tgeAmount;
        return
            (_linearVestingAmount / _totalReleaseMilestones) *
            _releaseMilestones +
            _info.tgeAmount;
    }

    function _releasableAmount(uint256 index) private view returns (uint256) {
        if (_revokedBeneficiaryIndexes.contains(index)) {
            return 0;
        }

        VestingInfo storage _info = _beneficiaries[index];
        return _vestedAmount(index) - _info.releasedAmount;
    }

    function _releaseAll() private {
        for (uint256 _index = 0; _index < _beneficiaries.length; _index++) {
            VestingInfo storage _info = _beneficiaries[_index];
            if (_info.beneficiary != address(0)) {
                uint256 _unreleaseAmount = _releasableAmount(_index);
                if (_unreleaseAmount > 0) {
                    _info.releasedAmount =
                        _info.releasedAmount +
                        _unreleaseAmount;
                    token.safeTransfer(_info.beneficiary, _unreleaseAmount);
                    emit TokensReleased(_info.beneficiary, _unreleaseAmount);
                }
            }
        }
    }

    function _releaseParticipant(Participant participant) private {
        for (uint256 _index = 0; _index < _beneficiaries.length; _index++) {
            VestingInfo storage _info = _beneficiaries[_index];
            if (
                _info.beneficiary != address(0) &&
                _info.participant == participant
            ) {
                uint256 _unreleaseAmount = _releasableAmount(_index);
                if (_unreleaseAmount > 0) {
                    _info.releasedAmount =
                        _info.releasedAmount +
                        _unreleaseAmount;
                    token.safeTransfer(_info.beneficiary, _unreleaseAmount);
                    emit TokensReleased(_info.beneficiary, _unreleaseAmount);
                }
            }
        }
    }

    function _release(uint256 index, address recipient) private {
        VestingInfo storage _info = _beneficiaries[index];
        uint256 _unreleaseAmount = _releasableAmount(index);
        if (_unreleaseAmount > 0) {
            _info.releasedAmount = _info.releasedAmount + _unreleaseAmount;
            token.safeTransfer(recipient, _unreleaseAmount);
            emit TokensReleased(recipient, _unreleaseAmount);
        }
    }

    /**
     * Only call this function when releasableAmountOfRole >= amount_
     */
    function _releaseTokensOfRole(
        bytes32 role,
        uint256 amount,
        address reicipient
    ) private {
        uint256 _amountToRelease = amount;

        for (
            uint256 _index = 0;
            _index < _beneficiaryRoleIndexes[role].length();
            _index++
        ) {
            uint256 _beneficiaryIndex = _beneficiaryRoleIndexes[role].at(
                _index
            );
            VestingInfo storage _info = _beneficiaries[_beneficiaryIndex];
            uint256 _unreleaseAmount = _releasableAmount(_beneficiaryIndex);

            if (_unreleaseAmount > 0) {
                if (_unreleaseAmount >= _amountToRelease) {
                    _info.releasedAmount =
                        _info.releasedAmount +
                        _amountToRelease;
                    break;
                } else {
                    _info.releasedAmount =
                        _info.releasedAmount +
                        _unreleaseAmount;
                    _amountToRelease -= _unreleaseAmount;
                }
            }
        }

        token.safeTransfer(reicipient, amount);
        emit TokensReleased(msg.sender, amount);
    }

    function _revoke(uint256 index) private {
        bool _success = _revokedBeneficiaryIndexes.add(index);
        if (_success) {
            VestingInfo storage _info = _beneficiaries[index];
            uint256 _unreleaseAmount = _info.totalAmount - _info.releasedAmount;
            if (_unreleaseAmount > 0) {
                token.safeTransfer(msg.sender, _unreleaseAmount);
            }
            emit BeneficiaryRevoked(index, _unreleaseAmount);
        }
    }

    function _validateVestingInfo(VestingInfo calldata info) private pure {
        require(
            info.genesisTimestamp > 0,
            "TokensVesting: genesisTimestamp is 0"
        );
        require(info.totalAmount >= info.tgeAmount, "TokensVesting: bad args");
        require(
            info.genesisTimestamp + info.cliff + info.duration <=
                type(uint256).max,
            "TokensVesting: out of uint256 range"
        );
        require(
            Participant(info.participant) > Participant.Unknown &&
                Participant(info.participant) < Participant.OutOfRange,
            "TokensVesting: participant out of range"
        );
        require(
            info.beneficiary != address(0) || info.role != 0,
            "TokensVesting: must specify beneficiary or role"
        );
    }
}

