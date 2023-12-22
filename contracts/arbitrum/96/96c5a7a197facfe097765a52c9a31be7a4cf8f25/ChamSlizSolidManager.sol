// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./Pausable.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";

contract ChamSlizSolidManager is Ownable, Pausable {
    using SafeERC20 for IERC20;

    address public keeper;
    address public voter;
    address public taxWallet;
    address public polWallet;
    address public daoWallet;

    event NewManager(
        address _keeper,
        address _voter,
        address _taxWallet,
        address _polWallet,
        address _daoWallet
    );

    /**
     * @dev Initializes the base strategy.
     * @param _keeper address to use as alternative owner.
     */
    constructor(
        address _keeper,
        address _voter,
        address _taxWallet,
        address _polWallet,
        address _daoWallet
    ) {
        keeper = _keeper;
        voter = _voter;
        taxWallet = _taxWallet;
        polWallet = _polWallet;
        daoWallet = _daoWallet;
    }

    // Checks that caller is either owner or keeper.
    modifier onlyManager() {
        require(
            msg.sender == owner() || msg.sender == keeper,
            "ChamSlizSolidManager: MANAGER_ONLY"
        );
        _;
    }

    // Checks that caller is either owner or keeper.
    modifier onlyVoter() {
        require(msg.sender == voter, "ChamSlizSolidManager: VOTER_ONLY");
        _;
    }

    function setManager(
        address _keeper,
        address _voter,
        address _taxWallet,
        address _polWallet,
        address _daoWallet
    ) external onlyManager {
        keeper = _keeper;
        voter = _voter;
        taxWallet = _taxWallet;
        polWallet = _polWallet;
        daoWallet = _daoWallet;
        emit NewManager(_keeper, _voter, _taxWallet, _polWallet, _daoWallet);
    }
}

