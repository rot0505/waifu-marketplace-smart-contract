// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const { ethers, upgrades } = require('hardhat');

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await run('compile');

  // We get the contract to deploy
  const accounts = await ethers.getSigners()
  console.log('Deploying with ', accounts[0].address)

  const ArrayLibraryFactory = await ethers.getContractFactory('ArrayLibrary')
  const arrayLibrary = await ArrayLibraryFactory.deploy()

  await arrayLibrary.deployed()

  console.log('ArrayLibrary Contract Address:', arrayLibrary.address)

  const TestTokenFactory = await ethers.getContractFactory('TestToken')
  const testToken = await TestTokenFactory.deploy()

  await testToken.deployed()

  console.log('Token Contract Address:', testToken.address)

  const AddressesFactory = await ethers.getContractFactory('Addresses', { libraries: { ArrayLibrary: arrayLibrary.address } })
  const addresses = await AddressesFactory.deploy()

  await addresses.deployed()

  console.log('Addresses Contract Address:', addresses.address)

  const ERC721Sale = await ethers.getContractFactory('ERC721Sale', { libraries: { ArrayLibrary: arrayLibrary.address } });
  const erc721Sale = await upgrades.deployProxy(ERC721Sale, [], { unsafeAllow: ['external-library-linking'] })

  await erc721Sale.deployed();

  console.log('ERC721Sale Contract Address:', erc721Sale.address)

  await (await erc721Sale.setTokenContractAddr(testToken.address)).wait()
  await (await erc721Sale.setAddressesContractAddr(addresses.address)).wait()

  const ERC721Auction = await ethers.getContractFactory('ERC721Auction', { libraries: { ArrayLibrary: arrayLibrary.address } });
  const erc721Auction = await upgrades.deployProxy(ERC721Auction, [], { unsafeAllow: ['external-library-linking'] })

  await erc721Auction.deployed();

  console.log('ERC721Auction Contract Address:', erc721Auction.address);

  await (await erc721Auction.setTokenContractAddr(testToken.address)).wait()
  await (await erc721Auction.setAddressesContractAddr(addresses.address)).wait()

  const ERC1155Sale = await ethers.getContractFactory('ERC1155Sale', { libraries: { ArrayLibrary: arrayLibrary.address } });
  const erc1155Sale = await upgrades.deployProxy(ERC1155Sale, [], { unsafeAllow: ['external-library-linking'] })

  await erc1155Sale.deployed();

  console.log('ERC1155Sale Contract Address:', erc1155Sale.address);

  await (await erc1155Sale.setTokenContractAddr(testToken.address)).wait()
  await (await erc1155Sale.setAddressesContractAddr(addresses.address)).wait()

  const ERC1155Auction = await ethers.getContractFactory('ERC1155Auction', { libraries: { ArrayLibrary: arrayLibrary.address } });
  const erc1155Auction = await upgrades.deployProxy(ERC1155Auction, [], { unsafeAllow: ['external-library-linking'] })

  await erc1155Auction.deployed();

  console.log('ERC1155Auction Contract Address:', erc1155Auction.address);

  await (await erc1155Auction.setTokenContractAddr(testToken.address)).wait()
  await (await erc1155Auction.setAddressesContractAddr(addresses.address)).wait()
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
