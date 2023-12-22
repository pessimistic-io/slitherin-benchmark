//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./RouterCrossTalk.sol";
import "./ERC1155.sol";
import "./IERC20.sol";

contract CERC1155 is ERC1155, RouterCrossTalk {
    address public owner;
    uint256 private _crossChainGasLimit;

    constructor(string memory uri_, address genericHandler_)
        ERC1155(uri_)
        RouterCrossTalk(genericHandler_)
    {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    function mint(
        address _to,
        uint256[] memory ids,
        uint256[] memory amounts
    ) public {
        _mintBatch(_to, ids, amounts, "");
    }

    function setLinker(address _linker) public onlyOwner {
        setLink(_linker);
    }

    function setFeesToken(address _feeToken) public onlyOwner {
        setFeeToken(_feeToken);
    }

    function _approveFees(address _feeToken, uint256 _amount) public onlyOwner {
        approveFees(_feeToken, _amount);
    }

    /**
     * @notice setCrossChainGasLimit Used to set CrossChainGasLimit
     * @param _gasLimit Amount of gasLimit that is to be set
     */
    function setCrossChainGasLimit(uint256 _gasLimit) public onlyOwner {
        _crossChainGasLimit = _gasLimit;
    }

    /**
     * @notice fetchCrossChainGasLimit Used to fetch CrossChainGasLimit
     * @return crossChainGasLimit that is set
     */
    function fetchCrossChainGasLimit() external view returns (uint256) {
        return _crossChainGasLimit;
    }

    /**
     * @notice transferCrossChain used to create a cross-chain transfer request
     * @param _chainID Router internal chain ID of the destination chain (https://dev.routerprotocol.com/important-parameters/supported-chains)
     * @param _recipient address of the recipient of the NFT on the destination chain
     * @param _ids NFT ids you want to transfer cross-chain
     * @param _amounts NFT amounts for specific ids you want to transfer cross-chain
     * @param _data arbitrary data for NFT minting on destination chain. (pass "" if none)
     */
    function transferCrossChain(
        uint8 _chainID,
        address _recipient,
        uint256[] memory _ids,
        uint256[] memory _amounts,
        bytes memory _data,
        uint256 _crossChainGasPrice
    ) public returns (bytes32) {
        (bool sent, bytes32 hash) = _sendCrossChain(
            _chainID,
            _recipient,
            _ids,
            _amounts,
            _data,
            _crossChainGasPrice
        );

        require(sent == true, "Unsuccessful");
        return hash;
    }

    /**
     * @notice _sendCrossChain This is an internal function to generate a cross chain communication request
     */
    function _sendCrossChain(
        uint8 _destChainID,
        address _recipient,
        uint256[] memory _ids,
        uint256[] memory _amounts,
        bytes memory _data,
        uint256 _crossChainGasPrice
    ) internal returns (bool, bytes32) {
        _burnBatch(msg.sender, _ids, _amounts);
        bytes4 _selector = bytes4(
            keccak256("receiveCrossChain(address,uint256[],uint256[],bytes)")
        );
        bytes memory data = abi.encode(_recipient, _ids, _amounts, _data);
        (bool success, bytes32 hash) = routerSend(
            _destChainID,
            _selector,
            data,
            _crossChainGasLimit,
            _crossChainGasPrice
        );

        return (success, hash);
    }

    /**
     * @notice _routerSyncHandler Handles cross-chain request received from any other chain
     * @param _selector Selector to interface.
     * @param _data Data to be handled.
     */
    function _routerSyncHandler(bytes4 _selector, bytes memory _data)
        internal
        virtual
        override
        returns (bool, bytes memory)
    {
        (
            address _recipient,
            uint256[] memory _ids,
            uint256[] memory _amounts,
            bytes memory data
        ) = abi.decode(_data, (address, uint256[], uint256[], bytes));
        (bool success, bytes memory returnData) = address(this).call(
            abi.encodeWithSelector(_selector, _recipient, _ids, _amounts, data)
        );
        return (success, returnData);
    }

    /**
     * @notice receiveCrossChain Creates `_amounts` tokens of token type `_ids` to `_recipient` on the destination chain
     *
     * NOTE: It can only be called by current contract.
     *
     * @param _recipient Address of the recipient on destination chain
     * @param _ids TokenIds
     * @param _amounts Number of tokens with `_ids`
     * @param _data Additional data used to mint on destination side
     */
    function receiveCrossChain(
        address _recipient,
        uint256[] memory _ids,
        uint256[] memory _amounts,
        bytes memory _data
    ) external isSelf {
        _mintBatch(_recipient, _ids, _amounts, _data);
    }

    /**
     * @notice replayTransaction Used to replay the transaction if it failed due to low gaslimit or gasprice
     * @param hash Hash returned by transferCrossChain function
     * @param crossChainGasLimit new crossChainGasLimit
     * @param crossChainGasPrice new crossChainGasPrice
     * NOTE gasLimit and gasPrice passed in this function should be greater than what was passed earlier
     */
    function replayTransaction(
        bytes32 hash,
        uint256 crossChainGasLimit,
        uint256 crossChainGasPrice
    ) internal {
        routerReplay(hash, crossChainGasLimit, crossChainGasPrice);
    }

    function recoverFeeTokens() external onlyOwner {
        address feeToken = this.fetchFeeToken();
        uint256 amount = IERC20(feeToken).balanceOf(address(this));
        IERC20(feeToken).transfer(owner, amount);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(IERC165, ERC1155)
        returns (bool)
    {
        return
            interfaceId == type(IERC1155).interfaceId ||
            interfaceId == type(IERC1155MetadataURI).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}

