import { CognitoIdentityProviderClient, SignUpCommand, ConfirmSignUpCommand, InitiateAuthCommand, ChangePasswordCommand, ForgotPasswordCommand, ConfirmForgotPasswordCommand } from "@aws-sdk/client-cognito-identity-provider";
import { fromCognitoIdentityPool } from "@aws-sdk/credential-providers";

const client = new CognitoIdentityProviderClient({
  region: import.meta.env.VITE_AWS_REGION,
  credentials: fromCognitoIdentityPool({
    clientConfig: { region: import.meta.env.VITE_AWS_REGION },
    identityPoolId: import.meta.env.VITE_COGNITO_IDENTITY_POOL_ID,
  }),
});

export const signUp = async (email: string, password: string, userAttributes: Record<string, string> = {}) => {
  const command = new SignUpCommand({
    ClientId: import.meta.env.VITE_COGNITO_CLIENT_ID,
    Username: email,
    Password: password,
    UserAttributes: Object.entries(userAttributes).map(([Name, Value]) => ({ Name, Value })),
  });
  return await client.send(command);
};

export const confirmSignUp = async (email: string, code: string) => {
  const command = new ConfirmSignUpCommand({
    ClientId: import.meta.env.VITE_COGNITO_CLIENT_ID,
    Username: email,
    ConfirmationCode: code,
  });
  return await client.send(command);
};

export const signIn = async (email: string, password: string) => {
  const command = new InitiateAuthCommand({
    AuthFlow: "USER_PASSWORD_AUTH",
    ClientId: import.meta.env.VITE_COGNITO_CLIENT_ID,
    AuthParameters: {
      USERNAME: email,
      PASSWORD: password,
    },
  });
  return await client.send(command);
};

export const changePassword = async (accessToken: string, oldPassword: string, newPassword: string) => {
  const command = new ChangePasswordCommand({
    AccessToken: accessToken,
    PreviousPassword: oldPassword,
    ProposedPassword: newPassword,
  });
  return await client.send(command);
};

export const forgotPassword = async (email: string) => {
  const command = new ForgotPasswordCommand({
    ClientId: import.meta.env.VITE_COGNITO_CLIENT_ID,
    Username: email,
  });
  return await client.send(command);
};

export const confirmPassword = async (email: string, code: string, newPassword: string) => {
  const command = new ConfirmForgotPasswordCommand({
    ClientId: import.meta.env.VITE_COGNITO_CLIENT_ID,
    Username: email,
    ConfirmationCode: code,
    Password: newPassword,
  });
  return await client.send(command);
};