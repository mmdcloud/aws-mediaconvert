import React, { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import * as cognito from './cognito';
import { useNavigate } from 'react-router-dom';

interface AuthContextType {
  user: any;
  isAuthenticated: boolean;
  loading: boolean;
  login: (email: string, password: string) => Promise<void>;
  logout: () => void;
  signUp: (email: string, password: string) => Promise<void>;
  confirmSignUp: (email: string, code: string) => Promise<void>;
  changePassword: (oldPassword: string, newPassword: string) => Promise<void>;
}

const AuthContext = createContext<AuthContextType>(null!);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<any>(null);
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [loading, setLoading] = useState(true);
  const navigate = useNavigate();

  useEffect(() => {
    const checkAuth = async () => {
      try {
        const session = localStorage.getItem('cognito_session');
        if (session) {
          setUser(JSON.parse(session));
          setIsAuthenticated(true);
        }
      } finally {
        setLoading(false);
      }
    };
    checkAuth();
  }, []);

  const login = async (email: string, password: string) => {
    const response = await cognito.signIn(email, password);
    if (response.AuthenticationResult) {
      const userData = {
        email,
        accessToken: response.AuthenticationResult.AccessToken,
        idToken: response.AuthenticationResult.IdToken,
      };
      localStorage.setItem('cognito_session', JSON.stringify(userData));
      setUser(userData);
      setIsAuthenticated(true);
      navigate('/dashboard');
    }
  };

  const logout = () => {
    localStorage.removeItem('cognito_session');
    setUser(null);
    setIsAuthenticated(false);
    navigate('/login');
  };

  const signUp = async (email: string, password: string) => {
    await cognito.signUp(email, password);
    navigate(`/confirm?email=${encodeURIComponent(email)}`);
  };

  const confirmSignUp = async (email: string, code: string) => {
    await cognito.confirmSignUp(email, code);
    navigate('/login');
  };

  const changePassword = async (oldPassword: string, newPassword: string) => {
    if (!user?.accessToken) throw new Error('Not authenticated');
    await cognito.changePassword(user.accessToken, oldPassword, newPassword);
  };

  const value = {
    user,
    isAuthenticated,
    loading,
    login,
    logout,
    signUp,
    confirmSignUp,
    changePassword,
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  return useContext(AuthContext);
}