# build
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY . .
RUN dotnet publish src/PrtgExporter.ConsoleApp/PrtgExporter.ConsoleApp.csproj -c Release -o /app

# runtime
FROM mcr.microsoft.com/dotnet/runtime:8.0
WORKDIR /app
COPY --from=build /app ./
EXPOSE 9705
ENTRYPOINT ["dotnet","PrtgExporter.ConsoleApp.dll"]