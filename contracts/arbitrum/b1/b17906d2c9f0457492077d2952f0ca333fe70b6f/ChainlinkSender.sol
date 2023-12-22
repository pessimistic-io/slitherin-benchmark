// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {LinkTokenInterface} from "./LinkTokenInterface.sol";
import {IRouterClient} from "./IRouterClient.sol";
import {Client} from "./Client.sol";
import {ArcBaseWithRainbowRoad} from "./ArcBaseWithRainbowRoad.sol";
import {IRainbowRoad} from "./IRainbowRoad.sol";

/**
 * Sends messages to the Chainlink CCIP router
 */
contract ChainlinkSender is ArcBaseWithRainbowRoad 
{
    enum PaymentTypes {
        NATIVE,
        LINK
    }

    IRouterClient public router;
    LinkTokenInterface public link;
    PaymentTypes public paymentType;
    mapping(address => bool) public admins;

    event MessageSent(bytes32 messageId, uint64 destinationChainSelector, address messageReceiver, string action, address actionRecipient);

    constructor(address _rainbowRoad, address _router, address _link) ArcBaseWithRainbowRoad(_rainbowRoad)
    {
        require(_router != address(0), 'Router cannot be zero address');
        require(_link != address(0), 'Link cannot be zero address');
        
        router = IRouterClient(_router);
        link = LinkTokenInterface(_link);
        paymentType = PaymentTypes.LINK;
    }
    
    function setRouter(address _router) external onlyOwner
    {
        require(_router != address(0), 'Router cannot be zero address');
        router = IRouterClient(_router);
    }

    function setLink(address _link) external onlyOwner
    {
        require(_link != address(0), 'Link cannot be zero address');
        link = LinkTokenInterface(_link);
    }
    
    function setPaymentTypeToLink() external onlyOwner
    {
        require(paymentType != PaymentTypes.LINK, 'Fees are already paid in LINK');
        paymentType = PaymentTypes.LINK;
    }
    
    function setPaymentTypeToNative() external onlyOwner
    {
        require(paymentType != PaymentTypes.NATIVE, 'Fees are already paid in NATIVE');
        paymentType = PaymentTypes.NATIVE;
    }
    
    function enableAdmin(address admin) external onlyOwner
    {
        require(!admins[admin], 'Admin is enabled');
        admins[admin] = true;
    }
    
    function disableAdmin(address admin) external onlyOwner
    {
        require(admins[admin], 'Admin is disabled');
        admins[admin] = false;
    }

    function send(uint64 destinationChainSelector, address messageReceiver, address actionRecipient, string calldata action, bytes calldata payload) external nonReentrant whenNotPaused onlyAdmins returns (bytes32 messageId)
    {
        return _send(destinationChainSelector, messageReceiver, actionRecipient, action, payload);
    }
    
    function send(uint64 destinationChainSelector, address messageReceiver, string calldata action, bytes calldata payload) external nonReentrant whenNotPaused returns (bytes32 messageId)
    {
        return _send(destinationChainSelector, messageReceiver, msg.sender, action, payload);
    }

    function _send(uint64 destinationChainSelector, address messageReceiver, address actionRecipient, string calldata action, bytes calldata payload) internal returns (bytes32 messageId)
    {
        require(messageReceiver != address(0), 'Message receiver cannot be zero address');

        rainbowRoad.sendAction(action, actionRecipient, payload);
        
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(messageReceiver),
            data: abi.encode(action, actionRecipient, payload),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: "",
            feeToken: paymentType == PaymentTypes.LINK ? address(link) : address(0)
        });

        uint256 fee = router.getFee(destinationChainSelector, message);

        if (paymentType == PaymentTypes.LINK) {
            link.approve(address(router), fee);
            messageId = router.ccipSend(destinationChainSelector, message);
        } else {
            messageId = router.ccipSend{value: fee}(destinationChainSelector, message);
        }

        emit MessageSent(messageId, destinationChainSelector, messageReceiver, action, actionRecipient);
    }
    
    /// @dev Only calls from the enabled admins are accepted.
    modifier onlyAdmins() 
    {
        require(admins[msg.sender], 'Invalid admin');
        _;
    }

    receive() external payable {}
}

