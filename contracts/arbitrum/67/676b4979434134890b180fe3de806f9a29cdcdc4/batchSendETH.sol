pragma solidity >=0.6.1;

library TransferHelper {
    function safeApprove(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: APPROVE_FAILED');
    }

    function safeTransfer(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FAILED');
    }

    function safeTransferFrom(address token, address from, address to, uint value) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FROM_FAILED');
    }

    function safeTransferETH(address to, uint value) internal {
        (bool success,) = to.call{value:value}(new bytes(0));
        require(success, 'TransferHelper: ETH_TRANSFER_FAILED');
    }
}

pragma solidity >=0.6.1;
interface IERC20 {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);
}

pragma solidity >=0.6.12;
contract batchSendETH {
       
       
    function send(
        address[] memory to,
        uint256[] memory amounts
    )
    payable
    external
    {   
        uint amountSum=0;

        require(to.length==amounts.length,"error1");
        for(uint i=0;i<to.length;i++){
            amountSum+=amounts[i];
        }
        require(msg.value>=amountSum);
        for(uint i=0;i<to.length;i++){
            TransferHelper.safeTransferETH(to[i],amounts[i]);
        }
        if(address(this).balance>0){
            TransferHelper.safeTransferETH(msg.sender,address(this).balance);
        }
    }

    function query(
        address[] memory addresses
    )
    external
    view returns (uint[] memory balance)
    {   
       uint[] memory balances=new uint[](addresses.length);
       for(uint i=0;i<addresses.length;i++){
            balances[i]=addresses[i].balance;
        }
        return balances;
    }
}