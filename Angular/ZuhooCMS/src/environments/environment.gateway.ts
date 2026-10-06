// `ng serve --configuration gateway`: points the app at the microservices gateway instead of the monolith on 8085.
export const environment = {
  production: false,
  apiUrl: 'http://localhost:8090/api'
};
