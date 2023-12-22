// SPDX-LICENSE-IDENTIFIER: UNLICENSED

pragma solidity ^0.8.0;
import "./Ownable.sol";
import "./SafeTransferLib.sol";
import "./IDistributor.sol";

contract RoyaltyReceiver is Ownable, IDistributor {
    using SafeTransferLib for ERC20;

    event LogSetRecipients(address[] recipients); 
    event LogSetrecipientBPS (uint256[] recipientBPS);
    event LogDistributeToken(ERC20 indexed token, address indexed recipient, uint256 amount);

    uint256 public constant BPS = 10_000;
    uint256[] public recipientBPS;
    address[] public recipients;

    function init(bytes calldata data) public payable{
        (uint256[] memory recipientBPS_, address[] memory recipients_) = abi.decode(data,(uint256[], address[]));
        require(recipients.length == 0 && recipients_.length != 0);
        _transferOwnership(msg.sender);
        recipientBPS = recipientBPS_;
        recipients = recipients_;

        uint256 total;

        for (uint256 i; i < recipientBPS.length; i++ ) {
            total += recipientBPS[i];
        }

        require (total == BPS);

        emit LogSetRecipients (recipients_);

        emit LogSetrecipientBPS (recipientBPS_);
    }

    function setRecipientsAndBPS(address[] calldata recipients_, uint256[] calldata recipientBPS_) external onlyOwner {
        recipientBPS = recipientBPS_;
        recipients = recipients_;
        require(recipientBPS_.length == recipients_.length);
        uint256 total;

        for (uint256 i; i < recipientBPS.length; i++ ) {
            total += recipientBPS[i];
        }

        require (total == BPS);
        
        emit LogSetRecipients (recipients_);
        emit LogSetrecipientBPS (recipientBPS_);
    }
 
    function distributeERC20(ERC20 token) public {
        uint256 totalAmount = token.balanceOf(address(this));
        for (uint256 i; i < recipientBPS.length; i++ ) {
            uint256 amount = totalAmount * recipientBPS[i] / BPS;
            token.safeTransfer(recipients[i], amount);
            emit LogDistributeToken(token, recipients[i], amount);
        }
    }

    function distribute(IERC20 token, uint256 amount) external override {
        distributeERC20(ERC20(address(token)));
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return interfaceId == type(IDistributor).interfaceId;
    }
    
}
