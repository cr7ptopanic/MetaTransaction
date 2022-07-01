const { BigNumber } = require('ethers')

module.exports = async ({ getNamedAccounts, deployments }) => {
    const {deploy} = deployments;
    const {deployer} = await getNamedAccounts();

    const protocolFee = BigNumber.from(10).pow(15)
    const feeReceiver = '0xFc12Cb9E81468e483b40D1d09C4219F9f430dE09'

    await deploy('Escrow', {
      from: deployer,
      args: [
        feeReceiver,
        protocolFee,
      ],
      log: true,
    });
  
  };
  
  module.exports.tags = ['Escrow'];
  