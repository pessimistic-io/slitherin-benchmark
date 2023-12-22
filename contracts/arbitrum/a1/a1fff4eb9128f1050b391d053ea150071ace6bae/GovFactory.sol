// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Gov} from "./Gov.sol";
import {GovToken} from "./GovToken.sol";
import {GovDeployer} from "./GovDeployer.sol";
import {TimelockController} from "./TimelockController.sol";

contract GovFactory {

    GovDeployer immutable govDeployer;

    /**
     * @notice Emitted when a DAO is created.
     * @param sender Address wants to deploy DAO. Is indexed for query event.
     * @param gov Governor deploy address.
     * @param timelock Timelock deploy address.
     * @param token Token deploy address.
    */ 
    event DAOCreated(
        address indexed sender,
        address gov,
        address timelock,
        address token
    );

    constructor(GovDeployer _govDeployer) {
        govDeployer = _govDeployer;
    }


    /**
     * @notice Deploy a Decentralized Autonomous Organization (DAO).
     * This function creates a new DAO by deploying the required contracts and setting them up.
     *
     * @param _tokenName The name of the governance token for the DAO.
     * @param _tokenSymbol The symbol of the governance token for the DAO.
     * @param _timelockDelay The delay in seconds for the TimelockController.
     * @param _name The name of the DAO.
     * @param _votingDelay The delay in blocks for voting in the DAO.
     * @param _votingPeriod The duration in block for each voting period in the DAO.
     * @param _quorumFraction The fraction of total tokens required for a proposal to be considered valid.
     * @param _proposalThreshold The threshold of votes required for a proposal to be approved.
     * @param _premint The amount of tokens to be minted and assigned to the msg.sender upon deployment.
     */
    function deployDao(
        string memory _tokenName,
        string memory _tokenSymbol,
        uint256 _timelockDelay,
        string memory _name,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _quorumFraction,
        uint256 _proposalThreshold,
        uint256 _premint
    ) public {
        
        GovToken token = new GovToken(_tokenName, _tokenSymbol);
        
        TimelockController timelock = new TimelockController(_timelockDelay, new address[](0), new address[](0),address(this));
        
        Gov gov = govDeployer.deploy(token,timelock,_name,_votingDelay,_votingPeriod,_quorumFraction,_proposalThreshold);

        setUpDao(timelock,gov,token,_premint);

        emit DAOCreated(msg.sender, address(gov), address(timelock), address(token));
   
    }

    /**
     * @dev Set up the deployed DAO by granting roles and transferring ownership of the governance token.
     * This function is called internally within the contract and is not meant to be called directly.
     *
     * @param _timelock The deployed TimelockController contract instance.
     * @param _gov The deployed Gov contract instance.
     * @param _token The deployed GovToken contract instance.
     * @param _premint The amount of tokens to be minted and assigned to msg.sender.
     * 
     * @dev To configure timelock, the admin must be the DAOFactory contract. Once configured it will renonce role to the governor. 
     */
    function setUpDao(
        TimelockController _timelock,
        Gov _gov,
        GovToken _token,
        uint256 _premint
    ) internal {
        bytes32 proposerRole = _timelock.PROPOSER_ROLE();
        bytes32 executorRole = _timelock.EXECUTOR_ROLE();
        bytes32 adminRole = _timelock.TIMELOCK_ADMIN_ROLE();

        ///As address(this) is admin of timelock, add roles to Governor
        _timelock.grantRole(proposerRole, address(_gov));
        _timelock.grantRole(executorRole, address(_gov));
        _timelock.grantRole(adminRole, msg.sender);
        _timelock.renounceRole(adminRole, address(this));

        _token.mint(msg.sender,_premint);
        _token.transferOwnership(address(_timelock));

    }

}

