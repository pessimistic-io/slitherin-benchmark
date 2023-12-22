// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.1;
import "./Ownable.sol";
import "./IWrapped.sol";
import "./IERC20.sol";
import "./IERC20Metadata.sol";
import "./IWrapped.sol";
import "./SafeERC20.sol";
import "./paraSwapper.sol";
import "./IUniswapV2Router.sol";

contract Spotme is Ownable, ParaSwapper {
    using SafeERC20 for IERC20Metadata;

    constructor(IAugustus _augustus) ParaSwapper(_augustus) {}

    event RequestEvent(
        address indexed requester,
        address indexed requested,
        address tokenRequested,
        uint256 amount,
        bytes message,
        string indexed requestType
    );

    enum Status {
        REQUESTED,
        FULFILLED,
        REJECTED
    }

    enum Role {
        REQUESTER,
        REQUESTEE
    }

    struct Request {
        Status status;
        address requester;
        address requestee;
        address tokenRequested;
        uint48 timeRequested;
        uint48 respondTime;
        uint256 amount;
        bytes message;
    }

    uint256 public swapFee; //start the fee at 0%
    uint256 public numRequests;
    address public weth = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;

    mapping(address => mapping(Role => uint256[])) public userData;
    mapping(uint256 => Request) public allRequests;

    function changeFee(uint256 _newFee) external onlyOwner {
        require(_newFee <= 50, "Value exceeds max fee");
        swapFee = _newFee;
    }

    function withdrawFees(address _token) external onlyOwner {
        uint256 tokenBalance = IERC20Metadata(_token).balanceOf(address(this));
        address _owner = owner();
        IERC20Metadata(_token).safeTransfer(_owner, tokenBalance);
    }

    function requestUser(
        address _requestee,
        address _tokenRequested,
        uint256 _amount,
        bytes calldata _message
    ) external {
        require(_tokenRequested != address(0), "Cannot request the zero token");
        require(
            _requestee != address(0),
            "Cannot request from the zero address"
        );
        require(_requestee != msg.sender, "Cannot request from yourself");
        require(_amount != 0, "Must request a positive number");
        Request memory request = Request({
            requester: msg.sender,
            requestee: _requestee,
            tokenRequested: _tokenRequested,
            status: Status.REQUESTED,
            timeRequested: uint48(block.timestamp),
            respondTime: 0,
            amount: _amount,
            message: _message
        });
        userData[msg.sender][Role.REQUESTER].push(numRequests);
        userData[_requestee][Role.REQUESTEE].push(numRequests);
        allRequests[numRequests] = request;
        numRequests++;
        emit RequestEvent(
            msg.sender,
            _requestee,
            _tokenRequested,
            _amount,
            _message,
            "request"
        );
    }

    function fulfillRequestWithAgg(
        address _tokenProvided,
        uint256 _id,
        uint256 _amountIn, 
        bytes calldata _data
    ) external {
        Request storage requestToFulfill = allRequests[_id];
        require(
            requestToFulfill.requester != msg.sender,
            "Signer cannot be requester"
        );
        require(requestToFulfill.status == Status.REQUESTED);
        uint256 total;
        if (_tokenProvided == requestToFulfill.tokenRequested) {
            total = (requestToFulfill.amount * (1000 + swapFee)) / 1000;
            IERC20Metadata(_tokenProvided).safeTransferFrom(
                msg.sender,
                address(this),
                total
            );
            IERC20Metadata(_tokenProvided).safeTransfer(
                requestToFulfill.requester,
                requestToFulfill.amount
            );
        } else {
            total = (_amountIn * (1000 + swapFee)) / 1000;
            IERC20Metadata(_tokenProvided).safeTransferFrom(
                msg.sender,
                address(this),
                total
            );
            ParaSwapper.paraSwap(
                IERC20Metadata(_tokenProvided),
                _amountIn,
                _data
            );
            IERC20Metadata(requestToFulfill.tokenRequested).safeTransfer(
                requestToFulfill.requester,
                requestToFulfill.amount
            );
            if (IERC20Metadata(_tokenProvided).balanceOf(address(this)) > (total - _amountIn)) { 
                IERC20Metadata(_tokenProvided).safeTransfer(msg.sender, (IERC20Metadata(_tokenProvided).balanceOf(address(this)) - (total - _amountIn))); 
                require(IERC20Metadata(_tokenProvided).balanceOf(address(this)) == (total - _amountIn), 'Improper Fee'); 
            }
        }
        requestToFulfill.status = Status.FULFILLED;
        requestToFulfill.respondTime = uint48(block.timestamp);
        emit RequestEvent(
            requestToFulfill.requester,
            msg.sender,
            requestToFulfill.tokenRequested,
            requestToFulfill.amount,
            requestToFulfill.message,
            "fulfilled"
        );
    }

    function fulfillRequest(
        address _router,
        address _tokenProvided,
        address[] calldata _path,
        uint256 _id,
        uint256 _amountInMax,
        uint256 _deadline
    ) external {
        Request storage requestToFulfill = allRequests[_id];
        require(
            requestToFulfill.requester != msg.sender,
            "Signer cannot be requester"
        );
        require(requestToFulfill.status == Status.REQUESTED);
        uint256 total;
        if (_path.length == 1) {
            total = (requestToFulfill.amount * (1000 + swapFee)) / 1000;
            IERC20Metadata(_tokenProvided).safeTransferFrom(
                msg.sender,
                address(this),
                total
            );
            IWETH(weth).withdraw(requestToFulfill.amount);
            safeTransferETH(
                requestToFulfill.requester,
                requestToFulfill.amount
            );
        } else if (_path.length == 0) {
            total = (requestToFulfill.amount * (1000 + swapFee)) / 1000;
            IERC20Metadata(_tokenProvided).safeTransferFrom(
                msg.sender,
                address(this),
                total
            );
            IERC20Metadata(_tokenProvided).safeTransfer(
                requestToFulfill.requester,
                requestToFulfill.amount
            );
        } else {
            require(
                _path[0] == _tokenProvided,
                "First token in path must be token provided"
            );
            if (requestToFulfill.tokenRequested == address(0)) {
                require(
                    _path[_path.length - 1] == weth,
                    "path must end in weth"
                );
            } else {
                require(
                    _path[_path.length - 1] == requestToFulfill.tokenRequested,
                    "Last token in path must be token requested"
                );
            }
            uint256 amountNeeded = IUniswapV2Router(_router).getAmountsIn(
                requestToFulfill.amount,
                _path
            )[0];
            total = (amountNeeded * (1000 + swapFee)) / 1000;
            require(amountNeeded <= _amountInMax, "actual amount exceeds max");
            IERC20Metadata(_tokenProvided).safeTransferFrom(
                msg.sender,
                address(this),
                total
            );
            IERC20Metadata(_tokenProvided).safeIncreaseAllowance(
                _router,
                amountNeeded
            );
            if (requestToFulfill.tokenRequested == address(0)) {
                IUniswapV2Router(_router).swapTokensForExactTokens(
                    requestToFulfill.amount,
                    amountNeeded,
                    _path,
                    address(this),
                    _deadline
                );
                IWETH(weth).withdraw(requestToFulfill.amount);
                safeTransferETH(
                    requestToFulfill.requester,
                    requestToFulfill.amount
                );
            } else {
                IUniswapV2Router(_router).swapTokensForExactTokens(
                    requestToFulfill.amount,
                    amountNeeded,
                    _path,
                    requestToFulfill.requester,
                    _deadline
                );
            }

            requestToFulfill.status = Status.FULFILLED;
            requestToFulfill.respondTime = uint48(block.timestamp);
            emit RequestEvent(
                requestToFulfill.requester,
                msg.sender,
                requestToFulfill.tokenRequested,
                requestToFulfill.amount,
                requestToFulfill.message,
                "fulfilled"
            );
        }
    }

    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(
            success,
            "TransferHelper::safeTransferETH: ETH transfer failed"
        );
    }

    function getUserDataByRole(
        address _user,
        Role _role
    ) external view returns (uint256[] memory) {
        return userData[_user][_role];
    }

    receive() external payable {}

    fallback() external payable {}
}

