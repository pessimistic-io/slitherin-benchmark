pragma solidity ^0.5.16;

import "./Address.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./IERC20.sol";

import "./Governable.sol";
import "./IProfitSharingReceiver.sol";


/**
 * A simple contract for receiving tokens for profit sharing. This contract is designed to pool rewards that will be
 * sent by governance to Ethereum mainnet for FARM buybacks
 */
contract ProfitSharingReceiverV1 is IProfitSharingReceiver, Governable {
    using SafeERC20 for IERC20;

    event WithdrawToken(address indexed token, address indexed receiver, uint amount);

    constructor(
        address _store
    )
    public
    Governable(_store) {}

    function withdrawTokens(address[] calldata _tokens) external onlyGovernance {
        address _governance = governance();
        for (uint i = 0; i < _tokens.length; ++i) {
            uint amount = IERC20(_tokens[i]).balanceOf(address(this));
            if (amount > 0) {
                IERC20(_tokens[i]).safeTransfer(_governance, amount);
                emit WithdrawToken(_tokens[i], _governance, amount);
            }
        }
    }

}

