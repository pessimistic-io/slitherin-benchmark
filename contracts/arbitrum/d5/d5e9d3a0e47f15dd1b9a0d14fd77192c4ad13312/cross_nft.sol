
import "./ERC721.sol";

interface ILayerZeroReceiver {
    function lzReceive(uint16 _srcChainId, bytes calldata _srcAddress, uint64 _nonce, bytes calldata _payload) external;
}

interface ILayerZeroEndpoint {
    function send(uint16 _dstChainId, bytes calldata _destination, bytes calldata _payload, address payable _refundAddress, address _zroPaymentAddress, bytes calldata _adapterParams) external payable;
    function estimateFees(uint16 _dstChainId, address _userApplication, bytes calldata _payload, bool _payInZRO, bytes calldata _adapterParam) external view returns (uint nativeFee, uint zroFee);
}

contract cross_nft is ILayerZeroReceiver,ERC721 {

    /*
        https://github.com/LayerZero-Labs/sdk/blob/08e7f5a1655372d127e4bf68317d559e4b011d20/packages/lz-sdk/src/enums/ChainId.ts#L57

        Arbitrum
        chainId: 110
        endpoint: 0x3c2269811836af69497E5F486A85D7316753cf62

        Base Goerli
        chainId: 10160
        endpoint: 0x6aB5Ae6822647046626e83ee6dB8187151E1d5ab
        
        GOERLI_MAINNET 
        chainId: 10121
        endpoint: 0xbfD2135BFfbb0B5378b56643c2Df8a87552Bfa23
    */

    mapping (address=>uint256) public nft_holder;
    uint32 mint_token_id;
    ILayerZeroEndpoint public endpoint;
    uint16 public dest_chain_id;
    address public recv_contract;

    constructor(string memory name_, string memory symbol_,address _endpoint,uint16 _dstChainId,address _recv_contract) ERC721(name_,symbol_) {
        endpoint = ILayerZeroEndpoint(_endpoint);
        dest_chain_id = _dstChainId;
        recv_contract = _recv_contract;
    }

    function free_mint() external payable returns (uint256) {
        require(nft_holder[msg.sender] < 1,"Mint NFT so More");

        uint256 token_id = uint256(keccak256(abi.encodePacked((msg.sender))));

        _safeMint(msg.sender,token_id);
        mint_token_id += 1;
        nft_holder[msg.sender] += 1;

        bytes memory message_data = abi.encode(msg.sender,token_id);
        bytes memory remoteAndLocalAddresses = abi.encodePacked(recv_contract, address(this));

        if (dest_chain_id != 0)
            endpoint.send{value:msg.value}(dest_chain_id,remoteAndLocalAddresses,message_data,payable(msg.sender),address(0x0),bytes(""));

        return token_id;
    }
    
    function estimateFee() public view returns (uint nativeFee, uint zroFee) {
        uint256 token_id = uint256(keccak256(abi.encodePacked((msg.sender))));
        bytes memory message_data = abi.encode(msg.sender,token_id);

        return endpoint.estimateFees(dest_chain_id, address(this), message_data, true, bytes(""));
    }
    
    function lzReceive(uint16 _srcChainId, bytes calldata _srcAddress, uint64 _nonce, bytes calldata _payload) external override {
        bytes memory address_record = _srcAddress;
        address call_endpoint;
        address call_address;

        assembly {
            call_endpoint := mload(add(address_record,20))
            call_address := mload(add(address_record,40))
        }

        require(msg.sender == address(endpoint), "invalid endpoint caller");
        
        address mint_address;
        uint256 token_id;

        (mint_address,token_id) = abi.decode(_payload,(address,uint256));

        require(nft_holder[mint_address] < 1,"Mint NFT so More");
        require(_ownerOf(token_id) == address(0x0),"address is own nft");

        _safeMint(mint_address,token_id);
        mint_token_id += 1;
        nft_holder[mint_address] += 1;
    }

}
