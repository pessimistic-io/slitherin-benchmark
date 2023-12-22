//SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import { ERC20 } from "./ERC20.sol";
import { Pausable } from "./Pausable.sol";
import "./ERC20Votes.sol";

import "./GovernanceErrors.sol";
import "./GovernanceInitiationData.sol";

/**
 * @title Cora Governance Token
 * @author Cora Dev Team
 * @notice This token is used to govern the Cora Protocol.
 * @dev The token is non transferable for a period of time after deployment.
 * This period is defined by the MINIMUM_NON_TRANSFERABILITY_PERIOD constant.
 */
contract CoraToken is ERC20, ERC20Votes, Pausable {
  uint256 public immutable MINIMUM_NON_TRANSFERABILITY_PERIOD = 120 days;

  uint256 public immutable canUnpauseAfter;

  GovernanceInitiationData private immutable initiationData;

  mapping(address => bool) public allowedTransferee;

  struct Recipient {
    address to;
    uint256 amount;
  }

  constructor(GovernanceInitiationData _initiationData, Recipient[] memory _recipients)
    ERC20("Cora", "CORA")
    ERC20Permit("Cora")
  {
    // @dev This means the token cannot be unpaused at least 120 days after deployment
    canUnpauseAfter = block.timestamp + MINIMUM_NON_TRANSFERABILITY_PERIOD;
    initiationData = _initiationData;

    // @dev Mint all tokens to the recipients and allow them to transfer them (airdrop, vestings)
    for (uint256 i = 0; i < _recipients.length; i++) {
      address to = _recipients[i].to;
      _mint(to, _recipients[i].amount);
      allowedTransferee[to] = true;
    }

    // @dev By default this token is paused or non transferable
    _pause();

    if (totalSupply() != 100_000_000 ether) {
      revert TokenBadInitialTotalSupply();
    }
  }

  modifier onlyDao() {
    if (msg.sender != initiationData.timelockAddress()) {
      revert OnlyDAO();
    }
    _;
  }

  function enableTransferability() external onlyDao {
    if (block.timestamp < canUnpauseAfter) {
      revert CoraTokenUnpauseNotReady();
    }
    _unpause();
  }

  function _afterTokenTransfer(address from, address to, uint256 amount)
    internal
    override(ERC20, ERC20Votes)
  {
    super._afterTokenTransfer(from, to, amount);
  }

  function _beforeTokenTransfer(address from, address to, uint256 amount) internal override(ERC20) {
    super._beforeTokenTransfer(from, to, amount);
    if (paused() && !(allowedTransferee[from])) {
      revert ProtocolPaused();
    }
  }

  function _mint(address to, uint256 amount) internal override(ERC20, ERC20Votes) {
    super._mint(to, amount);
  }

  function _burn(address account, uint256 amount) internal override(ERC20, ERC20Votes) {
    super._burn(account, amount);
  }
}

