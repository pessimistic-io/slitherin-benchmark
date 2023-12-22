// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "./NonBlockingReceiver.sol";
import "./ILayerZeroEndpoint.sol";
import "./ERC721.sol";
import "./Strings.sol";
import "./MerkleProof.sol";

// ******************************************************************************************************************************************************
// *************************************************************@@@@@*****/@@@@@@@@@@@@/*****************************************************************
// ***********************************************************@@./*/,&@@@* ...,****,... #@@@@/***********************************************************
// *********************************************************%@@@#@ ,..*...........*//*,,,,,..#@@@********************************************************
// *****************************************************@@@@% .......,,,.,*///..,,.......,,,,,,..@@@*****************************************************
// *************************************************&@@@,..,,,..,,,,,,,,,,,.//,,,............,,,,,.@@@***************************************************
// **********************************************(@@@ .,,,,,..,..**////.,,,,.,,,,,..............,,,,./@@#************************************************
// ********************************************%@@#.,,,,,,,..//*....////.,,,,.,,,,,,..............,,,,..@@#**********************************************
// *******************************************@@&.,,,,,,,,.//........//*.,,,,.,,,,,,,...............,,,,.*@@*********************************************
// /**************//**//////////////////////&@@ .,,,,,,,,.*..........///.,,,,.,,,,,,,.................,,,,.*@@(#*******************/*********************
// ///////////////////////////////////////*@@@..,,........ ////,,,,,.///.,,,,.,,,,,,,,..................,,,,.(..@@///////////////////////////////**&@&@%/
// ///////////////////////////////////////@@@..,,..////////////,,,,,.///.,,,,.,,,,,,,,,..................,..,*, @@/////////////////////////*/@@@(... @///
// //////////////////////////////////////#@@ /.,.,////////////*,,,,,.///.,,,,.,,,,,,,,,,,.................,.,...@@/////////////////////&@@& ..(&.%.@&////
// //////////////////////////////////////@@#,/.,./////////////,,,,,,.///.,,,,.,,,,,,,,,,,,,,,,,,,...../*,..,....@@//////////////////@@@ ./((& &&.@@//////
// /////////////////////////////////////(@@.*/.../////////////,,,,,,.///.,,,,,.,,,,,,,,,,,,,,...../,..*,,.,.....%@(//////////////@@@ .,*/&.&&& *@*///////
// /////////////////////////////////////&@@..*../////////////(,*#&*,.,///.,,,,,.,,,,,,,,,..,,../*.// ,,,.,,.....%@%///////////@@@ .,**/ &&&&.,@%/////////
// /////////////////////////////////////@@/,./*.&&//&&/%&////(*,,,,,,.///*.,,,,,,,....,,,,,...*.////.,,.,,..,...&@(////////@@@ ./((/ &&&&  @@////////////
// /////////////////////////////////////&@(.,./..//////////////,,,,,,..///*.,,,,,,,,,,,,..*...*//,.,,,,./..,,...@@//////@@@../((& &&&&. @@///////////////
// //////////////////////////////////////@@.,.*/../////////////,,,,,,,..*///..,,,,,,,../**..,..//.,,,.//..,,,...@@///@@@ ./((&.&&&&. @@#/////////////////
// //////////////////////////////////////@@ ,,.//../////////////,,,,,,,../////*/***/////...,,,.../////...,,,... @(@@@ ./((&.&&&&. @@@////////////////////
// ///////////////////////////////////////@@.,,.**./////////////*,,,,,,,,..*/////////,..,,,.,,,........,,,,,...@@@ .,((&,&&&&, @@@///////////////////////
// ///////////////////////////////////////#@&.,,././/////////////,,,,,,,,,,,.........,,,,,,,.,,,.......,,,,.... .,**/*&&&&*.@@@//////////////////////////
// ////////////////////////////////////////#@@.,,.. ////////******,,,,,,,,,,,,,,,,,,,,,,,,,,,.,,.......,,,,...,**/*//&&*.@@@/////////////////////////////
// /////////////////////////////////////////(@@.,,../***************,,,,,,,,,,,,,,,,,,,,,,,,,.,,,......,,,..../*////*.&@@////////////////////////////////
// ///////////////////////////////////////////@@.,,..****************,,,,,,,,,,,,,,,,,,,,,,,,.,,.......,,,....///*.%@@///////////////////////////////////
// ////////////////////////////////////////////@@ .,,.*****************,,,,,,,,,,,,,,,,,,,,,..,.......,,,.....*.#@@//////////////////////////////////////
// /////////////////////////////////////////////@@#.,,..*****************,,,,,,,,,,,,,,,,,,..,...,....,,,.... @@(////////////////////////////////////////
// (////////((((////////////////////////(/((//(//&@@.,,..******************,,,,,,,,,,,,,,,......,,....,,,.....@@/////////////////////////////////////////
// (////////((/((((((((((//////////(//////////////(@@.,,...********************,,,,,,,,........,,,....,,,.....@@///////////////////(/////////////////////
// (/(((((((((///////////////(////////////////////(/@@.,,,...**********************..........,,,,,....,,,,.....@@/(((////////((/((((//(///////////(//////
// ((((((((((((((((((((((((((((((((((((((((((((((((((@@.,,,./..****************,...........,,,,,,,....,,,,,.....@@&(((((((((((((((((((/(((/(/(/(/((((((((
// ((((((((((((((((((((((((((((((((((((((((((((((((((#@*.,,.//*..**********..............,,,,,,,,,....,,,,,,..... @@@/(((((((((((((((((((((((((((((((((((
// (((((((((((((((((((((((((((((((((((((((((((((((((((@@.,,,.////..........,,........*,,,,,,,,,,,,....,,,,,,,....... @@@@@&#((((/((((((((((((((((((((((((
// ((((((((((((((((((((((((((((((((((((((((((((((((((((@.,,,.////........,,...,*******,,,,,,,,,......*,...,,,,,................@@((&@@&((((((((((((((((((
// (((((((((((((((((((((((((((((((((((((((((((((((((((/@/.,,.///,.......... %(,.  .    .,*/*////...*.**.,,,.,,,,,.............%@@ .***/ .@@((((((((((((((
// (((((((((((((((((((((((((((((((((((((((((((((((((((/@/.,,.///........  &.%(%&#& &.*..**,/./....*,******,,..,,,,,..........&@ **.&@@& @@(@(((((((((((((
// (((((((((((((((((((((((((((((((((((((((((((((((((((@@.,,,.**.....,,.....*%#& &%%** % *..******.**..,,,,,,,...,,,,,,..... @@(,%.@@((@@.(&@(((((((((((((
// ((((((((((((((((((((((((((((((((((((((((((((((((((/@@.,,.*/,..,,**/.*&&&&&&&&&&//.,,.********,,,,,,,,,,,,,,.....,,,,,. @@(@@.*** @@@/@@(((((((((((((((
// ((((((((((((((((((((((((((((((((((((((((((((((((((@@ .,,,*.,/((%,*.#&&&&&&&&&&///...********,,,,,,,,,,,,,,,.,,,,,,,,..@@%(((@@.*%*,, @@(((((((((((((((
// (((((((((((((((((((((((((((/&@@@@@&%(((((((((((((@@,.,,.,/((%,*//.#&&&&&&&&&&&////..*****//,,,,,,,,,,,,,,,,.,,,,,,,,,,,,.&@#((#@@,.,,.@@((((((((((((((
// (((((((((((((((((((((((((((@/........&@%((((((((@@ ..,///%**/%&*.&&&&&&&&&&&&&(///,.****///,,,,,,,,,,,,/,,,.,,,,*,,,,,,,,,.&@%(((@&.,,,@((((((((((((((
// ((((((((((((((((((((((((((((@@ .#.### .@@((((%@@&.,///%**///,../&&&&&&&&&&&&&&&////.****///*,,,,,,,,,,,,,,.,,,,,,,,,,**,,,,, @@@@..,,.@@((((((((((((((
// (((((((((((((((((((((((((((((%@ .#*####..@@@@%.,///%/*///,...*&&&&&&&&&&&&&&&&&&///.*#**/*//,,,,.,,,,,,,.,,,,,,,,,,,*,,,,,,,..,,,,,..@@(((((((((((((((
// ((((((((((((((((((((((((((((((@@./ ##.#.#...,///&**///,....%&&&&&&&&&&&&&&&&&&&////..****.*****,,,,,..,,.***********.,,,,,,,,.@@@@@@((((((((((((((((((
// (((((((((((((((((((((((((((((@@..  #..# %.#..%/*///,.&...&&&&&&&&&&&&&&&&&&&&&/////..,...........*//,,*...,,,,,,,,..,*.,,,,,,.@@((((((((((((((((((((((
// ((((((((((((((((((((((((((((@@ , ./.%.( %%%.#..*...@,..&&&&&&&&&&&&&&&&&&&&&&/////*.,///,..,**.///*,..,,,,,,,,,,,,,,,,...,,,,.,@@&((((((((((((((((((((
// (((((((((((((((((((((((((((%@/.%..%%% ,/%%%%% # .(@..%&&&&&&&&&&&&&&&&&&&&&&&//////.////..****.//,,.,************,,,,,,.*.,,,,,.@@%(((((((((((((((((((
// (((((((((((((((((((((((((((@@.%%%%%%%/... ,###*.#.. &&&&&&&&&&&&&&&&&&&&&&&&////////*....*****,...********************,,./.,,,,.@@@(((((((((((((((((((
// (((((((((((((((#@@@@/ . #@@@.. %%%%%%%%%%,.. .,...&&&&&&&&&&&&&&&&&&&&&&&&///////////*..***,,,,,*,,,,,,,,,,,,,,,,,,*,***.///...@@@%(((((((((((((((((((
// (((((((((((@@,...,,,,,,,,,...,,..%%%%%.....,((*. &&&&&&&&&&&&&&&&&&&&&&&/////////////..,***,,,,,,,,,,,,,,,,,*,,,.,,,...,.//* @@@#(((((((((((((((((((((
// ((((((/@@@ .,,,*,.,*...,,,,,,,.... ........  (.(&&&&&&&&&&&&&&&&&&&&&&//////////////..,,,,,,,,,,,,,,,,,,........,.......,//.#@&(((((((((((((((((((((((
// ((((@@/...,,,..,,,,,,,,,,,,,,,,,.*@@@@&%#(/@@.%&&&&&&&&&&&&&&&&&&&&&///////////////...,,,,,,,,,,,,,,,...................///.@@((((((((((((((((((((((((

contract ImNoOne is ERC721, NonblockingReceiver, ILayerZeroUserApplicationConfig {
    using Strings for uint256;

    // We are cost efficient, you can mint 15 NFTs in one transaction
    uint256 public MAX_MINT_AT_ONCE = 15;

    uint256 nextTokenId = 1556;
    uint256 public maxMint = 2055;

    uint256 public publicMintPrice;

    bool public isPublicSaleOpen = false;
    bool public isRevealed = false;

    string public baseTokenURI;
    string BASE_METADATA_EXTENSION = ".json";

    constructor(
        string memory _initBaseUri,
        address _layerZeroEndpoint,
        uint256 _publicMintPrice
    ) ERC721("ImNoOne", "NOONE"){
        setBaseURI(_initBaseUri);
        endpoint = ILayerZeroEndpoint(_layerZeroEndpoint);
        publicMintPrice = _publicMintPrice;
    }

    // @notice Public mint function
    // @param _quantity You can mint more than one and save some gas!
    function mint(uint256 _quantity) external payable {
        require(isPublicSaleOpen == true, "Public sales not started");
        require(msg.value == publicMintPrice * _quantity, "Incorrect value sent");
        require(_quantity <= MAX_MINT_AT_ONCE, "Quantity limit");

        _mint(_quantity);
    }

    function _mint(uint256 _quantity) internal {
        require(tx.origin == msg.sender, "Self mint only");
        require(maxMint >= nextTokenId + _quantity - 1, "Ouch, sold out :( ");

        for (uint256 i = 1; i <= _quantity; i++) {
            _safeMint(msg.sender, nextTokenId - 1 + i);
        }
        nextTokenId += _quantity;
    }

    /// @notice Transfer the NFT from source chain to the destination chain
    /// @param _destinationChainId The chain id you want to transfer too
    /// @param _tokenId Your token id that want to transfer. You have to own it ;)
    function transferYourNoOneToAnotherChain(
        uint16 _destinationChainId,
        uint256 _tokenId
    ) public payable {
        require(msg.sender == ownerOf(_tokenId), "You must own the token to send it.");
        require(trustedSourceLookup[_destinationChainId].length != 0, "This chain is not supported.");
        require(isRevealed == true, "Wait for reveal in order to travel.");

        // Burn on the source chain. Don't worry, its only going to be burn if the transaction completes ;)
        _burn(_tokenId);

        bytes memory payload = abi.encode(msg.sender, _tokenId);

        // Calculate the gas needed to delivery your NFT in the other chain!
        uint16 version = 1;
        uint gas = 225000;
        bytes memory adapterParams = abi.encodePacked(version, gas);

        // LayerZero estimate fees for cross chain delivery
        (uint quotedLayerZeroFee,) = endpoint.estimateFees(_destinationChainId, address(this), payload, false, adapterParams);

        require(msg.value >= quotedLayerZeroFee, "Not enough gas to cover cross chain transfer.");

        endpoint.send {value : msg.value}(
            _destinationChainId,
            trustedSourceLookup[_destinationChainId], // destination address
            payload,
            payable(msg.sender), // refund address, if needed
            address(0x0),
            adapterParams
        );
    }

    function _baseURI() override internal view returns (string memory) {
        return baseTokenURI;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "URI query for nonexistent token");

        string memory baseURI = _baseURI();

        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString(), BASE_METADATA_EXTENSION)) : "";
    }

    // --------------------------- OWNER FUNCTIONS ---------------------------

    function setBaseURI(string memory _baseTokenURI) public onlyOwner {
        baseTokenURI = _baseTokenURI;
    }

    function togglePublicSale() public onlyOwner {
        isPublicSaleOpen = !isPublicSaleOpen;
    }

    function reveal(string memory _baseTokenURI) public onlyOwner {
        baseTokenURI = _baseTokenURI;
        isRevealed = true;
    }

    function reserve(uint256 _quantity) public onlyOwner {
        _mint(_quantity);
    }

    function setMaxMint(uint256 _maxMint) public onlyOwner {
        maxMint = _maxMint;
    }

    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        payable(msg.sender).transfer(balance);
    }

    function setPublicMintPrice(uint256 _price) external onlyOwner {
        publicMintPrice = _price;
    }

    // --------------------------- OMNICHAIN CODE ----------------------------------------

    function _LzReceive(uint16 _srcChainId, bytes memory _srcAddress, uint64 _nonce, bytes memory _payload) internal override {
        (address _dstOmnichainNFTAddress, uint256 omnichainNFT_tokenId) = abi.decode(_payload, (address, uint256));
        _safeMint(_dstOmnichainNFTAddress, omnichainNFT_tokenId);
    }

    function setConfig(
        uint16 _version,
        uint16 _chainId,
        uint256 _configType,
        bytes calldata _config
    ) external override onlyOwner {
        endpoint.setConfig(_version, _chainId, _configType, _config);
    }

    function setSendVersion(uint16 _version) external override onlyOwner {
        endpoint.setSendVersion(_version);
    }

    function setReceiveVersion(uint16 _version) external override onlyOwner {
        endpoint.setReceiveVersion(_version);
    }

    function forceResumeReceive(uint16 _srcChainId, bytes calldata _srcAddress) external override onlyOwner {
        endpoint.forceResumeReceive(_srcChainId, _srcAddress);
    }

    function renounceOwnership() public override onlyOwner {}
}

