/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  redirects:() => {
    return [
      {
        source:"/",
        destination:"/login",
        permanent:true
      }
    ]
  }
};

export default nextConfig;
