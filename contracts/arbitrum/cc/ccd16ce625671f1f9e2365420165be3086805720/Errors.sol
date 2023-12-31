// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

error BatchAuthenticationFailed();
error OrderDeadlineNotMet();
error DuplicateOrderHash();
error MinOutputAmountNotMet();
error OnlyOwner();
error OnlyNominee();
error OrderAlreadyFulfilled();
error FulfillDeadlineNotMet();
error InvalidSenderForTheOrder();
error NonSocketMessageInbound();
error ExtractedOrderAlreadyUnlocked();
error WrongOutoutToken();
error PromisedAmountNotMet();
error FulfillmentChainInvalid();
error SocketGatewayExecutionFailed();
error SolverNotWhitelisted();
error InvalidGatewayInboundCaller();
error InvalidSolver();
error InvalidGatewaySolver();
error InvalidRFQSolver();
error OrderAlreadyPrefilled();
error InboundOrderNotFound();
error OrderAlreadyCompleted();
error OrderNotClaimable();
error NotGatewayExtractor();
error InvalidOrder();

